// content.js

// 1. 核心 PluginLoader 逻辑 (双端共用)
const PluginLoader = (() => {
  const plugins = new Map();

  function register(plugin) {
    if (!plugin) {
      console.log(`[PluginLoader] ❌ 错误: 插件对象为空`);
      return;
    }
    try {
      plugin.setup(api(plugin.name));
      plugins.set(plugin.name, plugin);
      console.log(`[PluginLoader] ✅ ${plugin.name} loaded`);
    } catch (err) {
      console.log(`[PluginLoader] 💥 setup failed for ${plugin.name}: ${err.message || err}`);
    }
  }

  function unload(name) {
    const p = plugins.get(name);
    p?.teardown?.();
    plugins.delete(name);
  }

  function api(name) {
    return {
      on:  (evt, fn) => window.addEventListener(evt, fn, true),
      off: (evt, fn) => window.removeEventListener(evt, fn, true),
      log: (...a)    => console.log(`[${name}]`, ...a),
      
      // 【Debug】增加详细日志
      getStorage: async (keys) => {
        console.log(`[Appine-Debug] 📥 尝试读取 Storage:`, keys);
        if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
          const res = await chrome.storage.local.get(keys);
          console.log(`[Appine-Debug] 🟢 读取成功:`, res);
          return res;
        }
        console.log(`[Appine-Debug] 🔴 读取失败: chrome.storage 不存在 (可能缺少 permissions 或未刷新插件)`);
        return null;
      },
      setStorage: (data) => {
        console.log(`[Appine-Debug] 📤 尝试保存 Storage:`, data);
        if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
          chrome.storage.local.set(data, () => {
            console.log(`[Appine-Debug] 🟢 保存到 Chrome Storage 成功!`);
          });
        } else {
          console.log(`[Appine-Debug] 🔴 保存失败: chrome.storage 不存在`);
        }
      }
    };
  }

  return { register, unload, plugins };
})();

// 2. 暴露给全局 (专门为 iOS WKWebView 准备)
window.PluginLoader = PluginLoader;

// 3. 环境嗅探：如果是 Chrome 插件环境，则自动加载插件
if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getURL) {
  
  // 💡 在这里配置 Chrome 插件需要加载的目录
  const PLUGINS = [
    "selection-assistant",
    "link-hints"
  ];

  async function initChrome() {
    for (const name of PLUGINS) {
      try {
        const pluginUrl = chrome.runtime.getURL(`plugins/${name}/index.js`);
        const module = await import(pluginUrl);
        if (module.default) PluginLoader.register(module.default);
      } catch (e) {
        console.log(`[Appine-Plugin] ❌ 加载插件 ${name} 失败:`, e);
      }
    }
  }
  initChrome();
}
