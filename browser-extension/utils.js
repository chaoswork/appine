// utils.js
// Appine 全局工具库，供原生注入脚本和所有插件使用

window.AppineUtils = {
    /**
     * 判断元素是否可见
     * @param {HTMLElement} el 
     * @param {Object} options 配置项
     * @returns {boolean}
     */
    isElementVisible: function(el, options = {}) {
        // 默认全开（适用于 link-hints）
        const checkViewport = options.checkViewport !== undefined ? options.checkViewport : true;
        const checkSize = options.checkSize !== undefined ? options.checkSize : true;
        const checkPointerEvents = options.checkPointerEvents !== undefined ? options.checkPointerEvents : true;

        if (!el || el.nodeType !== Node.ELEMENT_NODE) return false;

        // 1. 计算样式检查 (最基础的隐藏判断)
        const style = window.getComputedStyle(el);
        if (
            style.display === 'none' ||
            style.visibility === 'hidden' ||
            style.opacity === '0'
        ) {
            return false;
        }

        if (checkPointerEvents && style.pointerEvents === 'none') {
            return false;
        }

        const rect = el.getBoundingClientRect();

        // 2. 基础尺寸检查 (Find 时可关闭，防止某些 overflow: visible 但 height: 0 的容器文本被漏掉)
        if (checkSize) {
            if (rect.width <= 0 || rect.height <= 0) return false;
        }

        // 3. 视口检查 (Find 时必须关闭，否则搜不到屏幕外的文本)
        if (checkViewport) {
            if (
                rect.bottom <= 0 || 
                rect.top >= (window.innerHeight || document.documentElement.clientHeight) ||
                rect.right <= 0 || 
                rect.left >= (window.innerWidth || document.documentElement.clientWidth)
            ) {
                return false;
            }
        }

        return true;
    }
};
