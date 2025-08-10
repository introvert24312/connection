(function () {
    'use strict';
    
    // 初始化 Mermaid
    if (window.mermaid) {
        mermaid.initialize({ 
            startOnLoad: false, 
            theme: 'dark',
            securityLevel: 'loose',
            fontFamily: 'system-ui, -apple-system, sans-serif',
            fontSize: 20,
            themeVariables: {
                primaryTextColor: '#eee',
                primaryBorderColor: '#666',
                primaryColor: '#111',
                background: 'transparent',
                fontFamily: 'system-ui, -apple-system, sans-serif',
                fontSize: '20px',
                // 流程图特定配置
                flowchart: {
                    fontSize: '20px',
                    nodeSpacing: 50,
                    rankSpacing: 50
                }
            }
        });
    }

    // Mermaid 重渲染函数
    function rerenderMermaid(root = document) {
        const els = root.querySelectorAll('.mermaid');
        
        els.forEach((el, index) => {
            try {
                // 获取源码
                let src = el.dataset.mmd || el.getAttribute('data-mmd') || el.textContent;
                
                // 如果已经是 SVG，尝试从原始源码重新渲染
                if (el.querySelector('svg')) {
                    // 清除现有 SVG
                    el.innerHTML = src || el.innerHTML;
                }
                
                // 确保源码不为空
                if (src && src.trim()) {
                    // 添加暗色主题配置（如果没有的话）
                    if (!src.includes('%%{init:') && !src.includes('theme:')) {
                        src = `%%{init: {'theme': 'dark'}}%%\n${src}`;
                    }
                    
                    // 设置源码
                    el.textContent = src;
                    el.dataset.mmd = src;
                }
                
            } catch (error) {
                console.warn('预处理 Mermaid 元素失败:', error, el);
            }
        });
        
        // 执行 Mermaid 渲染
        if (els.length && window.mermaid) {
            try {
                mermaid.init(undefined, els);
                
                // 渲染完成后强制应用暗色样式
                setTimeout(() => {
                    applyDarkStyles(root);
                }, 100);
                
            } catch (error) {
                console.warn('Mermaid 渲染失败:', error);
            }
        }
    }

    // 强制应用暗色样式
    function applyDarkStyles(root = document) {
        const svgs = root.querySelectorAll('.mermaid svg');
        
        svgs.forEach(svg => {
            // 确保 SVG 背景透明
            svg.style.background = 'transparent';
            
            // 应用暗色样式到各种元素
            const selectors = [
                'rect', 'circle', 'ellipse', 'polygon', 'path',
                'text', 'tspan', 'g.node', 'g.cluster'
            ];
            
            selectors.forEach(selector => {
                const elements = svg.querySelectorAll(selector);
                elements.forEach(el => {
                    // 根据元素类型应用样式
                    if (['rect', 'circle', 'ellipse', 'polygon'].includes(el.tagName.toLowerCase())) {
                        if (el.getAttribute('fill') !== 'none') {
                            el.style.fill = '#111';
                        }
                        el.style.stroke = '#666';
                    } else if (['text', 'tspan'].includes(el.tagName.toLowerCase())) {
                        el.style.fill = '#eee';
                    } else if (el.tagName.toLowerCase() === 'path') {
                        if (el.style.stroke !== 'none' && el.getAttribute('stroke') !== 'none') {
                            el.style.stroke = '#999';
                        }
                    }
                });
            });
        });
    }

    // DOM 加载完成后初次渲染
    document.addEventListener('DOMContentLoaded', () => {
        setTimeout(() => {
            rerenderMermaid();
            // 确保编辑器在 Mermaid 渲染完成后仍然可以编辑
            const vditorElement = document.querySelector('.vditor-ir');
            if (vditorElement) {
                vditorElement.setAttribute('contenteditable', 'true');
                console.log('编辑器可编辑状态已恢复');
            }
        }, 500);
    });

    // MutationObserver 监听 DOM 变化
    const observer = new MutationObserver(mutations => {
        let needsRerender = false;
        
        mutations.forEach(mutation => {
            mutation.addedNodes.forEach(node => {
                if (node.nodeType === 1) { // Element node
                    if (node.matches && node.matches('.mermaid')) {
                        needsRerender = true;
                    } else if (node.querySelector && node.querySelector('.mermaid')) {
                        needsRerender = true;
                    }
                }
            });
        });
        
        if (needsRerender) {
            // 延迟一点以确保 DOM 完全更新
            setTimeout(() => rerenderMermaid(), 200);
        }
    });

    // 开始观察
    observer.observe(document.body, { 
        childList: true, 
        subtree: true,
        characterData: true
    });

    // 全局主题切换函数
    window.applyDarkMode = function(isDark) {
        console.log('切换主题到:', isDark ? 'dark' : 'light');
        
        try {
            // 1. 切换 Vditor 主题
            if (window.vditor) {
                window.vditor.setTheme(
                    isDark ? 'dark' : 'classic',
                    isDark ? 'dark' : 'light',
                    isDark ? 'dracula' : 'github'
                );
            }
            
            // 2. 重新初始化 Mermaid
            if (window.mermaid) {
                mermaid.initialize({ 
                    startOnLoad: false, 
                    theme: isDark ? 'dark' : 'default',
                    securityLevel: 'loose',
                    fontFamily: 'system-ui, -apple-system, sans-serif',
                    fontSize: 20,
                    themeVariables: {
                        primaryTextColor: isDark ? '#eee' : '#333',
                        primaryBorderColor: isDark ? '#666' : '#333',
                        primaryColor: isDark ? '#111' : '#fff',
                        background: 'transparent',
                        fontFamily: 'system-ui, -apple-system, sans-serif',
                        fontSize: '20px',
                        // 流程图特定配置
                        flowchart: {
                            fontSize: '20px',
                            nodeSpacing: 50,
                            rankSpacing: 50
                        }
                    }
                });
            }
            
            // 3. 重新渲染所有 Mermaid 图表
            setTimeout(() => {
                rerenderMermaid();
            }, 300);
            
        } catch (error) {
            console.error('主题切换失败:', error);
        }
    };

    // 监听系统主题变化
    if (window.matchMedia) {
        const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
        
        mediaQuery.addEventListener('change', (e) => {
            window.applyDarkMode(e.matches);
        });
        
        // 初始化时应用当前主题
        setTimeout(() => {
            window.applyDarkMode(mediaQuery.matches);
        }, 100);
    }

    // 导出工具函数
    window.mermaidUtils = {
        rerender: rerenderMermaid,
        applyDarkStyles: applyDarkStyles
    };
    
    console.log('Mermaid 暗色渲染补丁已加载');
})();