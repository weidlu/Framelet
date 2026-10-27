/**
 * Framelet / 拾影 官网原生交互逻辑
 * 1. release.json 数据加载与状态呈现
 * 2. 精确框选、取色放大镜与原位工具栏互动演示
 * 3. 连续滚动长截图拼接模拟
 */

document.addEventListener('DOMContentLoaded', () => {
  initDownloadState();
  initViewfinderDemo();
});

/* -------------------------------------------------------------
 * 1. 动态加载 release.json 并更新下载卡片
 * ------------------------------------------------------------- */
function initDownloadState() {
  const downloadBtn = document.getElementById('primary-download-btn');
  const downloadStatusMsg = document.getElementById('download-status-msg');
  const releaseMetaText = document.getElementById('release-meta-text');

  fetch('release.json')
    .then(res => {
      if (!res.ok) throw new Error('Failed to load release.json');
      return res.json();
    })
    .then(data => {
      if (data.available === true && data.notarized === true && data.url) {
        // 当发布包已就绪且公证完成
        if (downloadBtn) {
          downloadBtn.classList.remove('btn-pending');
          downloadBtn.setAttribute('href', data.url);
          downloadBtn.removeAttribute('aria-disabled');
          downloadBtn.removeAttribute('role');
          downloadBtn.removeAttribute('tabindex');
          downloadBtn.innerHTML = `
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
            <span>下载 Framelet ${data.version}</span>
          `;
        }
        if (downloadStatusMsg) {
          downloadStatusMsg.innerHTML = `适用于 ${data.minimumOS} · ${data.architecture} · 官网独立分发`;
        }
        if (releaseMetaText) {
          releaseMetaText.innerHTML = `文件大小: ${data.size} · SHA-256: <code>${data.sha256.substring(0, 12)}...</code> · <a href="releases.html" style="text-decoration: underline;">完整校验信息</a>`;
        }
      } else {
        // 默认状态：DMG 正在构建与公证，下载即将开放
        if (downloadBtn) {
          downloadBtn.classList.add('btn-pending');
          downloadBtn.removeAttribute('href');
          downloadBtn.setAttribute('aria-disabled', 'true');
          downloadBtn.setAttribute('role', 'button');
          downloadBtn.setAttribute('tabindex', '0');
          downloadBtn.innerHTML = `
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
            <span>下载即将开放 (预览版准备中)</span>
          `;
        }
        if (downloadStatusMsg) {
          downloadStatusMsg.textContent = data.statusMessage || '安装包正在构建与公证流程准备中，公证通过后即在此开放下载。';
        }
        if (releaseMetaText) {
          releaseMetaText.innerHTML = `适用于 ${data.minimumOS} · ${data.architecture} · <a href="releases.html" style="text-decoration: underline;">查看版本计划与公证状态</a>`;
        }
      }
    })
    .catch(err => {
      console.warn('release.json 读取提示:', err);
      if (downloadBtn) {
        downloadBtn.classList.add('btn-pending');
        downloadBtn.removeAttribute('href');
        downloadBtn.setAttribute('aria-disabled', 'true');
        downloadBtn.innerHTML = `<span>下载即将开放 (v0.3.1 预览版)</span>`;
      }
    });
}

/* -------------------------------------------------------------
 * 2. 精确框选、长十字线、放大镜与长截图演示视窗
 * ------------------------------------------------------------- */
function initViewfinderDemo() {
  const stage = document.getElementById('demo-stage');
  if (!stage) return;

  const tabCrop = document.getElementById('tab-mode-crop');
  const tabLong = document.getElementById('tab-mode-long');
  const sceneCrop = document.getElementById('scene-crop');
  const sceneLong = document.getElementById('scene-long');

  // 十字线与放大镜元素
  const crosshairH = document.getElementById('crosshair-h');
  const crosshairV = document.getElementById('crosshair-v');
  const lens = document.getElementById('magnifier-lens');
  const coordDisplay = document.getElementById('coord-display');
  const hexDisplay = document.getElementById('hex-display');
  const rgbDisplay = document.getElementById('rgb-display');
  const copyToast = document.getElementById('copy-toast');

  // 选区与原位工具栏
  const cropBox = document.getElementById('crop-box');
  const inSituToolbar = document.getElementById('in-situ-toolbar');

  let currentX = 280;
  let currentY = 180;
  let isSelecting = false;
  let startX = 0;
  let startY = 0;
  let hasSelection = false;

  // 颜色模拟映射表（用于十字准星悬停取色）
  function getColorAt(x, y) {
    // 模拟根据坐标区域取样不同像素色值
    if (y < 120) return { hex: '#161B24', rgb: 'rgb(22, 27, 36)' };
    if (x > 200 && x < 480 && y > 150 && y < 330) {
      if (y > 220 && y < 270) return { hex: '#6366F1', rgb: 'rgb(99, 102, 241)' };
      return { hex: '#1F2937', rgb: 'rgb(31, 41, 55)' };
    }
    return { hex: '#0B0D11', rgb: 'rgb(11, 13, 17)' };
  }

  function updateCrosshairAndLens(x, y) {
    currentX = Math.round(x);
    currentY = Math.round(y);

    if (crosshairH) crosshairH.style.top = `${currentY}px`;
    if (crosshairV) crosshairV.style.left = `${currentX}px`;

    // 动态调整放大镜避免遮挡与边缘溢出
    if (lens) {
      const stageRect = stage.getBoundingClientRect();
      let lensLeft = currentX + 24;
      let lensTop = currentY + 24;
      if (lensLeft + 140 > stageRect.width) lensLeft = currentX - 160;
      if (lensTop + 140 > stageRect.height) lensTop = currentY - 160;

      lens.style.left = `${lensLeft}px`;
      lens.style.top = `${lensTop}px`;
      lens.style.opacity = hasSelection ? '0.35' : '1';
    }

    const color = getColorAt(currentX, currentY);
    if (coordDisplay) coordDisplay.textContent = `${currentX}, ${currentY}`;
    if (hexDisplay) hexDisplay.textContent = color.hex;
    if (rgbDisplay) rgbDisplay.textContent = color.rgb;
  }

  // 鼠标移动
  stage.addEventListener('mousemove', e => {
    if (sceneCrop.classList.contains('hidden')) return;
    const rect = stage.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
    const y = Math.max(0, Math.min(rect.height, e.clientY - rect.top));

    if (isSelecting && cropBox) {
      const left = Math.min(startX, x);
      const top = Math.min(startY, y);
      const width = Math.abs(x - startX);
      const height = Math.abs(y - startY);

      cropBox.style.display = 'block';
      cropBox.style.left = `${left}px`;
      cropBox.style.top = `${top}px`;
      cropBox.style.width = `${width}px`;
      cropBox.style.height = `${height}px`;

      if (inSituToolbar) inSituToolbar.style.display = 'none';
    } else {
      updateCrosshairAndLens(x, y);
    }
  });

  // 鼠标点击开始框选
  stage.addEventListener('mousedown', e => {
    if (sceneCrop.classList.contains('hidden') || e.button !== 0) return;
    stage.focus({ preventScroll: true });
    if (e.target.closest('#in-situ-toolbar')) return; // 点工具栏不重置

    const rect = stage.getBoundingClientRect();
    startX = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
    startY = Math.max(0, Math.min(rect.height, e.clientY - rect.top));
    isSelecting = true;
    hasSelection = false;
  });

  // 鼠标松开结束框选，弹出原位悬浮工具栏
  window.addEventListener('mouseup', e => {
    if (!isSelecting) return;
    isSelecting = false;

    if (cropBox && cropBox.style.display === 'block') {
      const width = parseInt(cropBox.style.width, 10);
      const height = parseInt(cropBox.style.height, 10);

      if (width > 20 && height > 20) {
        hasSelection = true;
        if (inSituToolbar) {
          inSituToolbar.style.display = 'inline-flex';
          // 确保工具栏不超出视窗底部
          const top = parseInt(cropBox.style.top, 10);
          const stageHeight = stage.clientHeight;
          if (top + height + 50 > stageHeight) {
            inSituToolbar.style.bottom = 'auto';
            inSituToolbar.style.top = '-46px';
          } else {
            inSituToolbar.style.top = 'auto';
            inSituToolbar.style.bottom = '-46px';
          }
        }
      } else {
        resetSelection();
      }
    }
  });

  function resetSelection() {
    if (cropBox) cropBox.style.display = 'none';
    if (inSituToolbar) inSituToolbar.style.display = 'none';
    hasSelection = false;
  }

  // 键盘支持：方向键 1px 微调，Shift 10px，G/R 取色
  stage.addEventListener('keydown', e => {
    if (sceneCrop.classList.contains('hidden')) return;

    // 方向键微调
    let delta = e.shiftKey ? 10 : 1;
    let handled = false;

    if (e.key === 'ArrowLeft') {
      currentX = Math.max(0, currentX - delta);
      handled = true;
    } else if (e.key === 'ArrowRight') {
      currentX = Math.min(stage.clientWidth, currentX + delta);
      handled = true;
    } else if (e.key === 'ArrowUp') {
      currentY = Math.max(0, currentY - delta);
      handled = true;
    } else if (e.key === 'ArrowDown') {
      currentY = Math.min(stage.clientHeight, currentY + delta);
      handled = true;
    } else if (e.key === 'g' || e.key === 'G') {
      showCopyToast(`示意色值 HEX: ${hexDisplay ? hexDisplay.textContent : '#6366F1'}`);
      handled = true;
    } else if (e.key === 'r' || e.key === 'R') {
      showCopyToast(`示意色值 RGB: ${rgbDisplay ? rgbDisplay.textContent : 'rgb(99, 102, 241)'}`);
      handled = true;
    } else if (e.key === 'Escape') {
      resetSelection();
      handled = true;
    }

    if (handled) {
      e.preventDefault();
      updateCrosshairAndLens(currentX, currentY);
    }
  });

  function showCopyToast(msg) {
    if (!copyToast) return;
    copyToast.textContent = msg;
    copyToast.style.opacity = '1';
    copyToast.style.transform = 'translateY(0)';
    setTimeout(() => {
      copyToast.style.opacity = '0';
      copyToast.style.transform = 'translateY(6px)';
    }, 2000);
  }

  // 工具栏工具按钮交互
  const toolBtns = document.querySelectorAll('.tool-btn[data-tool]');
  toolBtns.forEach(btn => {
    btn.addEventListener('click', e => {
      e.stopPropagation();
      toolBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    });
  });

  const confirmBtn = document.getElementById('btn-confirm-crop');
  if (confirmBtn) {
    confirmBtn.addEventListener('click', e => {
      e.stopPropagation();
      showCopyToast('演示完成；未读取屏幕或修改剪贴板');
      resetSelection();
    });
  }

  // 模式 Tab 切换
  if (tabCrop && tabLong) {
    tabCrop.addEventListener('click', () => {
      tabCrop.classList.add('active');
      tabCrop.setAttribute('aria-selected', 'true');
      tabLong.setAttribute('aria-selected', 'false');
      tabLong.classList.remove('active');
      sceneCrop.classList.remove('hidden');
      sceneLong.classList.remove('active');
      stopLongScrollSimulation();
    });

    tabLong.addEventListener('click', () => {
      tabLong.classList.add('active');
      tabLong.setAttribute('aria-selected', 'true');
      tabCrop.setAttribute('aria-selected', 'false');
      tabCrop.classList.remove('active');
      sceneCrop.classList.add('hidden');
      sceneLong.classList.add('active');
      startLongScrollSimulation();
    });
  }

  // 初始准星位置
  updateCrosshairAndLens(currentX, currentY);

  /* -------------------------------------------------------------
   * 3. 连续滚动长截图动态效果模拟
   * ------------------------------------------------------------- */
  let scrollTimer = null;
  const docInner = document.getElementById('scroll-inner-doc');
  const previewCanvas = document.getElementById('preview-canvas-mimic');
  const heightCounter = document.getElementById('preview-height-counter');
  let scrollOffset = 0;
  let stitchedHeight = 120;

  function startLongScrollSimulation() {
    stopLongScrollSimulation();
    scrollOffset = 0;
    stitchedHeight = 120;

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    scrollTimer = setInterval(() => {
      scrollOffset += 45;
      stitchedHeight += 30;

      if (scrollOffset > 320) {
        // 重置循环
        scrollOffset = 0;
        stitchedHeight = 120;
      }

      if (docInner) {
        docInner.style.transform = `translateY(-${scrollOffset}px)`;
      }
      if (previewCanvas) {
        previewCanvas.style.height = `${stitchedHeight}px`;
      }
      if (heightCounter) {
        heightCounter.textContent = `拼接分辨率: 1198 × ${stitchedHeight * 8} px (Retina 高清)`;
      }
    }, 1200);
  }

  function stopLongScrollSimulation() {
    if (scrollTimer) {
      clearInterval(scrollTimer);
      scrollTimer = null;
    }
  }
}
