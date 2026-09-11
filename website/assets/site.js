/* PIE-Block 介绍页交互
   三件事：背景粒子、生成结果面板的页签、复制按钮。
   无依赖，全部在 prefers-reduced-motion 下退化为静态。 */
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  /* ---------- 背景粒子 ---------- */
  function createField(canvas, options) {
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const opts = Object.assign(
      { density: 12000, minNodes: 12, maxNodes: 64, link: 132, alpha: 1, speed: 0.16 },
      options
    );

    let nodes = [];
    let width = 0;
    let height = 0;
    let raf = 0;
    let running = false;
    let visible = true;
    let resizeTimer = 0;

    const rgb = "63, 210, 228";

    function resize() {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = Math.max(rect.width, 1);
      height = Math.max(rect.height, 1);
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const count = Math.min(
        opts.maxNodes,
        Math.max(opts.minNodes, Math.round((width * height) / opts.density))
      );
      nodes = Array.from({ length: count }, () => ({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * opts.speed,
        vy: (Math.random() - 0.5) * opts.speed,
        r: 0.6 + Math.random() * 1.1,
      }));
    }

    function draw() {
      ctx.clearRect(0, 0, width, height);

      for (let i = 0; i < nodes.length; i++) {
        const a = nodes[i];
        for (let j = i + 1; j < nodes.length; j++) {
          const b = nodes[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist > opts.link) continue;
          ctx.strokeStyle =
            "rgba(" + rgb + ", " + (1 - dist / opts.link) * 0.1 * opts.alpha + ")";
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
          ctx.stroke();
        }
      }

      ctx.fillStyle = "rgba(" + rgb + ", " + 0.45 * opts.alpha + ")";
      for (const n of nodes) {
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    function step() {
      for (const n of nodes) {
        n.x += n.vx;
        n.y += n.vy;
        if (n.x < -24) n.x = width + 24;
        else if (n.x > width + 24) n.x = -24;
        if (n.y < -24) n.y = height + 24;
        else if (n.y > height + 24) n.y = -24;
      }
      draw();
      raf = requestAnimationFrame(step);
    }

    function start() {
      if (running || reduceMotion.matches) return;
      running = true;
      raf = requestAnimationFrame(step);
    }

    function stop() {
      running = false;
      cancelAnimationFrame(raf);
      raf = 0;
    }

    function sync() {
      if (visible && !document.hidden && !reduceMotion.matches) start();
      else stop();
    }

    resize();
    draw();

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(
        (entries) => {
          visible = entries.some((entry) => entry.isIntersecting);
          sync();
        },
        { threshold: 0 }
      ).observe(canvas);
    }

    document.addEventListener("visibilitychange", sync);

    if (typeof reduceMotion.addEventListener === "function") {
      reduceMotion.addEventListener("change", () => {
        sync();
        if (reduceMotion.matches) draw();
      });
    }

    window.addEventListener("resize", () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        stop();
        resize();
        draw();
        sync();
      }, 160);
    });

    sync();
  }

  createField(document.getElementById("hero-canvas"), {
    density: 11000,
    maxNodes: 72,
    link: 138,
    alpha: 1,
  });

  createField(document.getElementById("closing-canvas"), {
    density: 16000,
    maxNodes: 44,
    link: 150,
    alpha: 0.8,
    speed: 0.12,
  });

  /* ---------- 生成结果面板的页签 ---------- */
  document.querySelectorAll(".terminal__tabs").forEach((tablist) => {
    const tabs = Array.from(tablist.querySelectorAll('[role="tab"]'));
    const terminal = tablist.closest(".terminal");
    if (!terminal || tabs.length === 0) return;

    const panes = Array.from(terminal.querySelectorAll(".terminal__pane"));

    function select(tab) {
      const targetId = tab.getAttribute("aria-controls");
      tabs.forEach((item) => {
        item.setAttribute("aria-selected", String(item === tab));
        item.tabIndex = item === tab ? 0 : -1;
      });
      panes.forEach((pane) => {
        pane.dataset.active = String(pane.id === targetId);
      });
    }

    tabs.forEach((tab, index) => {
      tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1;
      tab.addEventListener("click", () => select(tab));
      tab.addEventListener("keydown", (event) => {
        const offset = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
        if (offset === 0) return;
        event.preventDefault();
        const next = tabs[(index + offset + tabs.length) % tabs.length];
        select(next);
        next.focus();
      });
    });
  });

  /* ---------- 复制按钮 ---------- */
  function setCopyLabel(button, text) {
    const span = button.querySelector("span");
    if (span) {
      span.textContent = text;
      return;
    }
    // 没有 span 时只改末尾的文本节点，保留前面图标
    const textNode = Array.from(button.childNodes)
      .reverse()
      .find((node) => node.nodeType === Node.TEXT_NODE && node.textContent.trim());
    if (textNode) textNode.textContent = text;
  }

  async function writeClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (error) {
        /* 继续走 execCommand 回退 */
      }
    }
    try {
      const scratch = document.createElement("textarea");
      scratch.value = text;
      scratch.setAttribute("readonly", "");
      scratch.style.position = "fixed";
      scratch.style.top = "-1000px";
      document.body.appendChild(scratch);
      scratch.select();
      const ok = document.execCommand("copy");
      scratch.remove();
      return ok;
    } catch (error) {
      return false;
    }
  }

  document.querySelectorAll("[data-copy], [data-copy-pane]").forEach((button) => {
    button.addEventListener("click", async () => {
      let text = button.dataset.copy;

      if (button.hasAttribute("data-copy-pane")) {
        const terminal = button.closest(".terminal");
        const pane =
          terminal && terminal.querySelector('.terminal__pane[data-active="true"]');
        text = pane ? pane.textContent : "";
      }

      if (!text) return;

      const ok = await writeClipboard(text);
      setCopyLabel(button, ok ? button.dataset.copyLabel || "已复制" : "复制失败");

      clearTimeout(button.copyResetTimer);
      button.copyResetTimer = setTimeout(() => setCopyLabel(button, "复制"), 1600);
    });
  });

  /* ---------- 滚动揭示 ---------- */
  const reveals = Array.from(document.querySelectorAll(".reveal"));
  const revealAll = () =>
    reveals.forEach((element) => element.classList.add("is-visible"));

  if (reduceMotion.matches || !("IntersectionObserver" in window)) {
    revealAll();
  } else {
    let fired = false;
    const observer = new IntersectionObserver(
      (entries) => {
        fired = true;
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.06 }
    );
    reveals.forEach((element) => observer.observe(element));

    // 兜底：观察器一次都没回调时（渲染被挂起等极端情况）直接放行全部内容
    setTimeout(() => {
      if (!fired) revealAll();
    }, 2500);
  }
})();
