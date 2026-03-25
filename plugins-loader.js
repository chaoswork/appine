// plugins-loader.js
const PluginLoader = (() => {
  const plugins = new Map();

  // 直接注册插件对象，使用 import() 可能出错
  function register(plugin) {
    if (!plugin) {
      console.log(`[PluginLoader] ❌ ERROR: plugin object is null`);
      return;
    }
    try {
      plugin.setup(api(plugin.name));
      plugins.set(plugin.name, plugin);
      console.log(`[PluginLoader] ✅ ${plugin.name} loaded and setup`);
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
    };
  }

  return { register, unload, plugins };
})();

window.PluginLoader = PluginLoader;
