'use strict';

document.documentElement.classList.add('js');

const captions = {
  all: '一次框选，箭头、方框、文字、马赛克与遮挡可以叠加使用。',
  arrow: '箭头：指向重点，比多说一句更直接。',
  box: '方框：把需要注意的地方框出来。',
  text: '文字：直接在截图上写一句备注。',
  mosaic: '马赛克：弱化不重要的细节。',
  redact: '遮挡：不透明覆盖，适合手机号、账号等敏感信息。'
};
const shotButtons = document.querySelectorAll('[data-shot]');
const shotImages = document.querySelectorAll('[data-shot-image]');
const shotCaption = document.querySelector('#shot-caption');

for (const button of shotButtons) {
  button.addEventListener('click', () => {
    const shot = button.dataset.shot;
    for (const item of shotButtons) item.setAttribute('aria-pressed', String(item === button));
    for (const image of shotImages) image.classList.toggle('is-active', image.dataset.shotImage === shot);
    shotCaption.textContent = captions[shot];
  });
}

const header = document.querySelector('.site-header');
const onScroll = () => header.classList.toggle('is-scrolled', window.scrollY > 8);
window.addEventListener('scroll', onScroll, { passive: true });
onScroll();

const revealItems = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -60px 0px', threshold: 0 });
  for (const item of revealItems) observer.observe(item);
} else {
  for (const item of revealItems) item.classList.add('is-visible');
}

// Only the landing page has the release dialog and the FAQ; privacy.html shares this script.
const dialog = document.querySelector('#release-dialog');
const releaseInfo = document.querySelector('#release-info');
if (dialog && releaseInfo) {
  releaseInfo.addEventListener('click', () => dialog.showModal());
  // Allow an outside click to dismiss without interfering with clicks inside the dialog.
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
}
for (const link of document.querySelectorAll('a[href="#privacy-question"]')) {
  link.addEventListener('click', () => { const question = document.querySelector('#privacy-question'); if (question) question.open = true; });
}

async function updateRelease() {
  try {
    const response = await fetch('release.json', { cache: 'no-cache' });
    if (!response.ok) throw new Error('release metadata unavailable');
    const release = await response.json();
    const downloadURL = typeof release.url === 'string' ? new URL(release.url, location.href) : null;
    const safeURL = downloadURL && ['http:', 'https:'].includes(downloadURL.protocol);
    const available = release.available === true && safeURL;
    for (const link of document.querySelectorAll('[data-download]')) {
      if (available) {
        link.href = downloadURL.href;
        link.removeAttribute('aria-disabled');
      } else {
        link.removeAttribute('href');
        link.removeAttribute('download');
        link.setAttribute('aria-disabled', 'true');
        link.querySelector('span').textContent = '下载暂未开放';
      }
    }
    if (typeof release.version === 'string') {
      for (const item of document.querySelectorAll('[data-version]')) item.textContent = release.version;
    }
    if (typeof release.size === 'string') {
      for (const item of document.querySelectorAll('[data-size]')) item.textContent = release.size;
    }
    const checksum = document.querySelector('#checksum');
    if (checksum && /^[a-f0-9]{64}$/i.test(release.sha256 || '')) checksum.value = release.sha256;
    const status = document.querySelector('#release-status');
    if (status) status.textContent = available
      ? '同时适配 Apple Silicon 与 Intel Mac'
      : (release.statusMessage || '安装包正在准备中，请稍后再来。');
  } catch {
    // The packaged, verified links remain usable if metadata refresh fails.
    const status = document.querySelector('#release-status');
    if (status) status.textContent = '当前提供 0.3.1 预览版；如下载失败，请稍后重试。';
  }
}
updateRelease();
