/* @ds-bundle: {"format":4,"namespace":"Ginga","components":[{"name":"Button"},{"name":"Switch"},{"name":"SettingsGroup"},{"name":"StatusOrbit"},{"name":"PairingCode"},{"name":"Segmented"},{"name":"DeviceRow"},{"name":"Starfield"}]} */
(function () {
  "use strict";
  var reduce = false;
  try { reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) {}

  /* Céu estrelado em canvas. Barato: uma camada, DPR limitado a 1.5,
     pausa quando a aba some ou o elemento sai da tela. */
  function starfield(canvas, opts) {
    opts = opts || {};
    var density = opts.density || 0.00022, drift = opts.drift == null ? 0.012 : opts.drift;
    var ctx = canvas.getContext("2d"), stars = [], w = 0, h = 0, dpr = 1, raf = 0, visible = true, t0 = 0;
    var palette = opts.colors || ["242,243,248", "242,243,248", "242,243,248", "111,130,255", "255,196,61"];
    function resize() {
      var r = canvas.getBoundingClientRect();
      dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      w = Math.max(1, r.width); h = Math.max(1, r.height);
      canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      var n = Math.round(w * h * density); stars = [];
      for (var i = 0; i < n; i++) {
        stars.push({ x: Math.random() * w, y: Math.random() * h, z: Math.random(), r: Math.random() * 1.1 + 0.3,
          p: Math.random() * 6.28, s: 0.6 + Math.random() * 1.6, c: palette[(Math.random() * palette.length) | 0] });
      }
      draw(0);
    }
    function draw(t) {
      ctx.clearRect(0, 0, w, h);
      for (var i = 0; i < stars.length; i++) {
        var s = stars[i];
        var a = reduce ? 0.7 : 0.35 + 0.55 * (0.5 + 0.5 * Math.sin(s.p + t * 0.001 * s.s));
        var x = reduce ? s.x : (s.x + t * drift * (0.3 + s.z)) % w;
        ctx.fillStyle = "rgba(" + s.c + "," + (a * (0.4 + s.z * 0.6)).toFixed(3) + ")";
        ctx.beginPath(); ctx.arc(x, s.y, s.r * (0.6 + s.z * 0.6), 0, 6.283); ctx.fill();
      }
    }
    function loop(t) { if (!t0) t0 = t; draw(t - t0); raf = visible ? requestAnimationFrame(loop) : 0; }
    function start() { if (!raf && !reduce && visible && !document.hidden) raf = requestAnimationFrame(loop); }
    function stop() { if (raf) cancelAnimationFrame(raf); raf = 0; }
    resize();
    var ro = window.ResizeObserver ? new ResizeObserver(resize) : null; if (ro) ro.observe(canvas);
    if (window.IntersectionObserver) {
      new IntersectionObserver(function (e) { visible = e[0].isIntersecting; visible ? start() : stop(); }).observe(canvas);
    }
    document.addEventListener("visibilitychange", function () { document.hidden ? stop() : start(); });
    start();
    return { stop: stop, start: start, resize: resize };
  }

  /* Faísca de estrela: 7 partículas saindo do centro de el. */
  function spark(el, count) {
    if (reduce || !el) return;
    var host = el.offsetParent || document.body, r = el.getBoundingClientRect(), hr = host.getBoundingClientRect();
    var s = document.createElement("span"); s.className = "g-spark";
    s.style.left = (r.left - hr.left + r.width / 2) + "px"; s.style.top = (r.top - hr.top + r.height / 2) + "px";
    count = count || 7;
    for (var i = 0; i < count; i++) {
      var a = (i / count) * 6.283 + Math.random() * 0.5, d = 16 + Math.random() * 12, dot = document.createElement("i");
      dot.style.setProperty("--dx", (Math.cos(a) * d).toFixed(1) + "px");
      dot.style.setProperty("--dy", (Math.sin(a) * d).toFixed(1) + "px");
      s.appendChild(dot);
    }
    host.appendChild(s);
    setTimeout(function () { s.remove(); }, 600);
  }

  /* Liga um .g-seg: move o thumb sob o botão ativo. */
  function segmented(root, onChange) {
    var thumb = root.querySelector(".g-seg__thumb"), btns = root.querySelectorAll("button");
    function place(b) { thumb.style.width = b.offsetWidth + "px"; thumb.style.transform = "translateX(" + (b.offsetLeft - 3) + "px)"; }
    Array.prototype.forEach.call(btns, function (b) {
      if (b.getAttribute("aria-pressed") === "true") place(b);
      b.addEventListener("click", function () {
        Array.prototype.forEach.call(btns, function (o) { o.setAttribute("aria-pressed", String(o === b)); });
        place(b); if (onChange) onChange(b.value || b.textContent);
      });
    });
    /* as fontes da web mudam a largura dos rótulos: reposiciona quando carregam */
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () {
      var on = root.querySelector('button[aria-pressed="true"]'); if (on) place(on);
    });
  }

  /* Monta o HTML do código de pareamento em dois grupos. */
  function pairingCode(digits) {
    var d = String(digits).replace(/\D/g, "").slice(0, 6), g = function (s) {
      return '<span class="g-code__group">' + s.split("").map(function (c) { return '<span class="g-code__d">' + c + "</span>"; }).join("") + "</span>";
    };
    return '<span class="g-code" aria-label="Código ' + d.split("").join(" ") + '">' + g(d.slice(0, 3)) + g(d.slice(3)) + "</span>";
  }

  window.Ginga = { starfield: starfield, spark: spark, segmented: segmented, pairingCode: pairingCode, reducedMotion: reduce };
})();
