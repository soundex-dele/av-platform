// Run from any directory. Uses the existing headless test dependency; no desktop UI.
// node render.cjs <absolute path to mermaid.min.js> [browser executable]
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../../..');
const { chromium } = require(path.join(root, 'livekit-cpp/tests/node_modules/playwright'));
const markdown = fs.readFileSync(path.join(__dirname, 'README.md'), 'utf8');
const sections = [...markdown.matchAll(/^## (\d{2}) · (.+)\n([\s\S]*?)(?=^## |$(?![\s\S]))/gm)]
  .map((m) => {
    const diagram = /```mermaid\n([\s\S]*?)```/.exec(m[3]);
    if (!diagram) throw new Error(`Missing diagram ${m[1]}`);
    return { id: m[1], title: m[2], source: diagram[1], notes: m[3].replace(diagram[0], '') };
  });
if (sections.length !== 15) throw new Error(`Expected 15 diagrams; found ${sections.length}`);
const esc = (s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
function inline(s) {
  return esc(s).replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
}
const notes = (s) => s.trim().split(/\n\s*\n/).map(p => `<p>${inline(p)}</p>`).join('\n');
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.argv[3] || 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
  try {
    const page = await browser.newPage({ viewport: { width: 1800, height: 1200 }, deviceScaleFactor: 1 });
    await page.setContent('<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#fff}</style><main id="render"></main>');
    await page.addScriptTag({ path: path.resolve(process.argv[2]) });
    await page.evaluate(() => mermaid.initialize({
      startOnLoad: false, securityLevel: 'strict', theme: 'base',
      fontFamily: 'Microsoft YaHei, Segoe UI, sans-serif',
      themeVariables: { primaryColor: '#eef4fc', primaryTextColor: '#172b4d', primaryBorderColor: '#6585b0', lineColor: '#536579', secondaryColor: '#f4f7fa', tertiaryColor: '#f6f9fc', fontSize: '16px' },
      class: { useMaxWidth: false, htmlLabels: false, nodeSpacing: 40, rankSpacing: 55 }
    }));
    const report = [];
    for (const section of sections) {
      const result = await page.evaluate(async ({ id, source }) => {
        await mermaid.parse(source);
        const result = await mermaid.render(`diagram${id}`, source);
        document.querySelector('#render').innerHTML = result.svg;
        const svg = document.querySelector('#render svg');
        svg.setAttribute('role', 'img');
        const box = svg.viewBox.baseVal;
        return { svg: svg.outerHTML, width: box.width, height: box.height, nodes: svg.querySelectorAll('.node').length };
      }, section);
      fs.writeFileSync(path.join(__dirname, `${section.id}.svg`), result.svg);
      section.svg = result.svg;
      report.push({ id: section.id, title: section.title, width: result.width, height: result.height, nodes: result.nodes });
      if (section.id === '01' || section.id === '00') {
        await page.evaluate(() => {
          const svg = document.querySelector('#render svg');
          svg.style.width = '1600px'; svg.style.height = 'auto';
        });
        await page.locator('#render svg').screenshot({ path: path.join(__dirname, section.id === '00' ? 'sdk-overview.png' : 'overview.png') });
      }
      console.log(`Rendered ${section.id}: ${Math.round(result.width)} x ${Math.round(result.height)}`);
    }
    const contents = sections.map(s => `<a href="#section-${s.id}"><b>${s.id}</b> ${esc(s.title)}</a>`).join('\n');
    const cards = sections.map(s => `<section id="section-${s.id}"><div class="section-top"><h2>${s.id} · ${esc(s.title)}</h2><div class="actions"><button data-action="minus" aria-label="缩小">−</button><button data-action="fit">适应</button><button data-action="plus" aria-label="放大">＋</button><a href="${s.id}.svg" target="_blank" rel="noopener">打开 SVG ↗</a></div></div><div class="diagram">${s.svg}</div><div class="notes">${notes(s.notes)}</div></section>`).join('\n');
    const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SDK 类图 · conference_viewer</title><style>
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:24px}body{margin:0;color:#172b4d;background:#f3f6fa;font:15px/1.75 'Microsoft YaHei','Segoe UI',sans-serif}aside{position:fixed;inset:0 auto 0 0;width:260px;padding:28px 20px;background:#fff;border-right:1px solid #dce4ef;overflow:auto}aside strong{display:block;font-size:18px;margin-bottom:20px}aside a{display:block;padding:8px 10px;margin:3px 0;color:#334861;text-decoration:none;border-radius:6px}aside a:hover{background:#edf3fb}aside b{color:#55749d;margin-right:8px}main{margin-left:260px;padding:40px;max-width:2200px}h1{font-size:32px;line-height:1.3;margin:0 0 12px}header{margin-bottom:30px}header p{max-width:1100px}h2{font-size:21px;margin:0}a{color:#245b98}section{background:#fff;border:1px solid #dce4ef;border-radius:10px;padding:24px;margin:0 0 30px;scroll-margin-top:24px}.section-top{display:flex;justify-content:space-between;gap:16px;align-items:center;flex-wrap:wrap}.actions{display:flex;gap:8px;align-items:center}.actions a{font-size:13px;margin-left:8px}button{font:inherit;cursor:pointer;background:#fff;border:1px solid #b7c6d9;border-radius:5px;padding:3px 12px;color:#29445f}button:hover{background:#edf3fb}.diagram{overflow:auto;padding:20px 0;margin:20px 0;border-top:1px solid #edf1f6;border-bottom:1px solid #edf1f6}.diagram svg{display:block;width:100%;height:auto;max-width:none!important}.notes{color:#3e5167}.notes p{margin:12px 0}.legend{padding:16px 20px;background:#eaf1fa;border-radius:8px;max-width:1200px}code{background:#eff3f7;padding:2px 5px;border-radius:4px;font-size:13px}footer{color:#66778b;font-size:13px}@media(max-width:1000px){aside{position:static;width:auto;border-right:0;border-bottom:1px solid #dce4ef}aside nav{display:grid;grid-template-columns:repeat(2,minmax(0,1fr))}main{margin:0;padding:20px}section{padding:16px}.diagram svg{min-width:800px}}@media print{aside,.actions{display:none}main{margin:0;padding:0}section{break-before:page;border:0}.diagram{overflow:visible}.diagram svg{width:100%!important;min-width:0!important}body{background:#fff}}
</style></head><body><aside><strong>SDK 类图导航</strong><nav>${contents}</nav><hr><a href="README.md">Mermaid 源码与说明</a></aside><main><header><h1>从 conference_viewer 看 SDK</h1><p>15 张源码类图 · 2026-10-30 · 当前实现。图 00 为 SDK 全模块总览，图 01–09 为会议主链路及公共契约；图 10–14 标明可选或独立模块。SVG 已嵌入本文件，离线可浏览。</p><div class="legend"><b>关系：</b>实心菱形＝值成员或独占所有权；空心菱形＝共享引用；实线箭头＝借用或关联；虚线箭头＝调用、创建或事件交接；空心三角＝继承。<br>成员名与 namespace 在必要处标注；私有 Impl 可折叠。局部对象以“创建/局部对象”依赖标注，不冒充成员。</div></header>${cards}<footer>来源：同级 README.md 中的 Mermaid 与源码链接。渲染验证不等于设备或运行时验收。</footer></main><script>
document.querySelectorAll('button[data-action]').forEach(button=>button.addEventListener('click',()=>{const svg=button.closest('section').querySelector('.diagram svg');let scale=Number(svg.dataset.scale||1);scale=button.dataset.action==='fit'?1:Math.max(.5,Math.min(4,scale+(button.dataset.action==='plus'?.25:-.25)));svg.dataset.scale=scale;svg.style.width=(scale*100)+'%';}));
</script></body></html>`;
    fs.writeFileSync(path.join(__dirname, 'index.html'), html);
    await page.goto(pathToFileURL(path.join(__dirname, 'index.html')).href);
    const checks = await page.evaluate(() => ({
      sections: document.querySelectorAll('section').length,
      svgs: document.querySelectorAll('.diagram svg').length,
      missingDiagrams: [...document.querySelectorAll('.diagram')].filter(d => !d.querySelector('svg')).length,
      pageOverflow: document.documentElement.scrollWidth > innerWidth
    }));
    await page.locator('#section-01 button[data-action="plus"]').click();
    checks.zoomWorks = await page.locator('#section-01 .diagram svg').evaluate(s => s.style.width === '125%');
    await page.locator('#section-01 button[data-action="fit"]').click();
    if (checks.sections !== 15 || checks.svgs !== 15 || checks.missingDiagrams || checks.pageOverflow || !checks.zoomWorks) throw new Error(JSON.stringify(checks));
    const links = [...markdown.matchAll(/\]\((\.\.\/[^)]+)\)/g)].map(m => m[1]);
    checks.sourceLinks = links.length;
    checks.missingSourceLinks = links.filter(p => !fs.existsSync(path.resolve(__dirname, p)));
    if (checks.missingSourceLinks.length) throw new Error(`Missing sources: ${checks.missingSourceLinks}`);
    fs.writeFileSync(path.join(__dirname, 'validation.json'), JSON.stringify({ renderer: 'mermaid 10.9.3 / headless Chromium', checks, diagrams: report }, null, 2));
    console.log(JSON.stringify(checks));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
