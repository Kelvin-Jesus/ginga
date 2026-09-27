/* @ds-bundle: {"format":4,"namespace":"Ginga","components":[{"name":"Button"},{"name":"Switch"},{"name":"SettingsGroup"},{"name":"StatusOrbit"},{"name":"PairingCode"},{"name":"Segmented"},{"name":"DeviceRow"},{"name":"Starfield"},{"name":"DitherSpace"}]} */
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

  /* ===== Espaço em dithering pixelizado (Bayer 4×4 na paleta da marca) =====
     ditherLoop(canvas, shade) desenha um "shader" em baixa resolução; o canvas é ampliado com
     image-rendering: pixelated. blackHole() e galaxy(opts) são os shaders; pixelSky(canvas) é o céu em pixels. */
  function pixelSky(cv) {
      var PX = 4, ctx = cv.getContext("2d"), W = 0, H = 0, stars = [], shoot = null, raf = 0, last = 0, visible = true;
      var COL = ["#252C66", "#2E47F5", "#6F82FF", "#A4A9C8", "#F2F3F8", "#FFC43D"];
      var rm = !!(window.Ginga && window.Ginga.reducedMotion);
      var seed = function () {
        var r = cv.getBoundingClientRect(); W = Math.max(1, Math.ceil(r.width / PX)); H = Math.max(1, Math.ceil(r.height / PX));
        cv.width = W; cv.height = H; stars = [];
        var n = Math.round(W * H * 0.0048);
        for (var i = 0; i < n; i++) {
          var k = Math.random(), c = k < 0.5 ? 0 : k < 0.74 ? 1 : k < 0.88 ? 2 : k < 0.95 ? 3 : k < 0.99 ? 4 : 5;
          stars.push({ x: (Math.random() * W) | 0, y: (Math.random() * H) | 0, c: c, p: Math.random() * 6.28, s: 0.5 + Math.random() * 2, big: c >= 4 && Math.random() < 0.25 });
        }
        draw(0);
      };
      var draw = function (t) {
        ctx.clearRect(0, 0, W, H);
        for (var i = 0; i < stars.length; i++) {
          var st = stars[i], tw = Math.sin(st.p + t * st.s), c = st.c + (tw > 0.75 ? 1 : tw < -0.6 ? -1 : 0);
          if (c < 0) continue; if (c > 5) c = 5;
          ctx.fillStyle = COL[c]; ctx.fillRect(st.x, st.y, 1, 1);
          if (st.big && tw > 0.2) { ctx.fillStyle = COL[Math.max(0, c - 2)]; ctx.fillRect(st.x - 1, st.y, 1, 1); ctx.fillRect(st.x + 1, st.y, 1, 1); ctx.fillRect(st.x, st.y - 1, 1, 1); ctx.fillRect(st.x, st.y + 1, 1, 1); }
        }
        if (shoot) {
          var e = t - shoot.t0, len = 14;
          if (e > 1.1) shoot = null; else {
            var hx = shoot.x + e * shoot.vx, hy = shoot.y + e * shoot.vy;
            for (var j = 0; j < len; j++) { ctx.fillStyle = COL[j < 2 ? 5 : j < 5 ? 4 : j < 9 ? 2 : 1]; ctx.fillRect(Math.round(hx - j * shoot.vx / 60), Math.round(hy - j * shoot.vy / 60), 1, 1); }
          }
        } else if (Math.random() < 0.004) {
          shoot = { t0: t, x: Math.random() * W * 0.7, y: Math.random() * H * 0.35, vx: 90 + Math.random() * 60, vy: 30 + Math.random() * 30 };
        }
      };
      var t0 = performance.now();
      var loop = function (now) { raf = 0; if (!visible || document.hidden) return; if (now - last > 90) { last = now; draw((now - t0) / 1000); } raf = requestAnimationFrame(loop); };
      seed();
      var ro = window.ResizeObserver ? new ResizeObserver(seed) : null; if (ro) ro.observe(cv);
      if (!rm) {
        raf = requestAnimationFrame(loop);
        if (window.IntersectionObserver) new IntersectionObserver(function (en) { visible = en[0].isIntersecting; if (visible && !raf) raf = requestAnimationFrame(loop); }).observe(cv);
        document.addEventListener("visibilitychange", function () { if (!document.hidden && !raf) raf = requestAnimationFrame(loop); });
      }
      return { stop: function () { if (raf) cancelAnimationFrame(raf); raf = 0; visible = false; if (ro) ro.disconnect(); } };
    }
  
    /* dithering (Bayer 4×4) sobre a paleta da marca ---------- */
  
  function ditherLoop(cv, shade) {
      var ctx = cv.getContext("2d"), W = cv.width, H = cv.height, img = ctx.createImageData(W, H), d = img.data;
      var PAL = [[10,12,28],[20,24,48],[46,71,245],[111,130,255],[242,243,248],[255,196,61]], N = PAL.length - 1;
      var B = [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5];
      var geo = shade.init(W, H), buf = new Float32Array(W * H), raf = 0, visible = true, last = 0, t0 = performance.now();
      var rm = window.Ginga && (window.Ginga && window.Ginga.reducedMotion);
      var draw = function (t) {
        for (var j = 0; j < buf.length; j++) buf[j] = shade.at(geo, j, t);
        if (shade.splat) shade.splat(buf, W, H, t);
        for (var y = 0, i = 0; y < H; y++) for (var x = 0; x < W; x++, i++) {
          var v = buf[i], th = (B[(y & 3) * 4 + (x & 3)] + 0.5) / 16;
          var lv = Math.floor(v * N + th); lv = lv < 0 ? 0 : lv > N ? N : lv;
          var c = PAL[lv], o = i * 4; d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = lv === 0 ? 0 : 255;
        }
        ctx.putImageData(img, 0, 0);
      };
      var loop = function (now) {
        raf = 0; if (!visible || document.hidden) return;
        if (now - last > 42) { last = now; draw((now - t0) / 1000); }
        raf = requestAnimationFrame(loop);
      };
      draw(0);
      if (!rm) {
        raf = requestAnimationFrame(loop);
        if (window.IntersectionObserver) new IntersectionObserver(function (e) { visible = e[0].isIntersecting; if (visible && !raf) raf = requestAnimationFrame(loop); }).observe(cv);
        document.addEventListener("visibilitychange", function () { if (!document.hidden && !raf) raf = requestAnimationFrame(loop); });
      }
      return { shade: shade, now: function () { return (performance.now() - t0) / 1000; }, stop: function () { if (raf) cancelAnimationFrame(raf); raf = 0; visible = false; } };
    }
  
  function blackHole() {
      /* Buraco negro em dithering: gás espiralando para dentro (disco inclinado com efeito Doppler),
         anel de fótons, arco lenteado por cima, estrelas de fundo deformadas pela lente
         e ~700 partículas em órbita kepleriana que colapsam com o mouse e explodem no clique. */
      var R = 0.28, K = 0.2, rIn = 0.42, rOut = 1.6;
      var hash = function (a, b) { var x = Math.sin(a * 127.1 + b * 311.7) * 43758.5453; return x - Math.floor(x); };
      var shade = {
        pull: 0, pullT: 0, tb: -99, cx: 0, cy: 0, W: 0, H: 0,
        init: function (W, H) {
          var n = W * H, g = { x: new Float32Array(n), y: new Float32Array(n), rd: new Float32Array(n), lrd: new Float32Array(n), ang: new Float32Array(n), rs: new Float32Array(n), st: new Float32Array(n) };
          shade.W = W; shade.H = H; shade.cx = W * 0.5; shade.cy = H * 0.52;
          for (var yy = 0, i = 0; yy < H; yy++) for (var xx = 0; xx < W; xx++, i++) {
            var x = (xx - shade.cx) / (H / 2), y = (yy - shade.cy) / (H / 2), v = y / K, rs = Math.sqrt(x * x + y * y);
            g.x[i] = x; g.y[i] = y; g.rd[i] = Math.sqrt(x * x + v * v); g.lrd[i] = Math.log(g.rd[i] + 0.001); g.ang[i] = Math.atan2(v, x); g.rs[i] = rs;
            /* lente: a estrela vista aqui vem de um ponto empurrado para fora (Einstein) */
            var k = rs > R ? 1 + 0.09 / (rs * rs) : 0, sx = x * k, sy = y * k;
            var h = hash(Math.floor(sx * 60), Math.floor(sy * 60));
            g.st[i] = rs > R * 1.1 && rs < 1.05 && h > 0.985 ? 0.28 + (h - 0.985) * 40 : 0;
          }
          var P = [], NP = Math.min(700, Math.round(W * H * 0.03));
          for (var p = 0; p < NP; p++) {
            var r0 = rIn * 0.9 + Math.pow(Math.random(), 0.8) * (rOut * 1.25 - rIn);
            P.push({ r: r0, a: Math.random() * 6.2832, w: 0.9 / Math.pow(r0, 1.5), b: 0.35 + Math.random() * 0.55, z: (Math.random() - 0.5) * 0.05 });
          }
          g.P = P;
          return g;
        },
        at: function (g, i, t) {
          var x = g.x[i], y = g.y[i], rd = g.rd[i], a = g.ang[i], rs = g.rs[i];
          var dop = 0.5 - 0.5 * Math.cos(a);
          var D = 0;
          if (rd > rIn && rd < rOut) {
            var f = 1 - (rd - rIn) / (rOut - rIn);
            /* espirais que puxam o gás para dentro */
            var sw = 0.5 + 0.5 * Math.sin(a * 3 + g.lrd[i] * 7 + t * 2.2);
            var sw2 = 0.5 + 0.5 * Math.sin(a * 7 - g.lrd[i] * 11 + t * 3.1);
            D = Math.pow(f, 1.05) * (0.35 + 0.75 * dop) * (0.45 + 0.4 * sw + 0.2 * sw2) * Math.min(1, (rd - rIn) / 0.06);
          }
          var L = 0, dr = Math.abs(rs - 0.47);
          if (dr < 0.17 && y < 0.05) {
            var la = Math.atan2(y, x);
            L = Math.pow(1 - dr / 0.17, 1.4) * (0.55 + 0.45 * (0.5 - 0.5 * Math.cos(la))) * (0.7 + 0.3 * Math.sin(la * 5 + t * 2.4 + rs * 20));
          }
          var Pr = Math.max(0, 1 - Math.abs(rs - R * 1.04) / 0.02);
          if (rs < R) return (y > 0 && D > 0) ? D : 0;
          var halo = 0.18 * Math.exp(-(rs - R) / 0.14) * (1 + 0.6 * shade.pull);
          var back = Math.min(1, Math.max(0, (rs - 0.5) / 0.3)); back = back * back * (3 - 2 * back);
          var v = Math.max(y > 0 ? D : Math.max(D * back, L), Pr * (0.85 + 0.15 * Math.sin(t * 3)), halo);
          v += g.st[i] * (0.65 + 0.35 * Math.sin(t * 1.7 + i));
          return v > 1 ? 1 : v;
        },
        splat: function (buf, W, H, t) {
          var g = shade.g; if (!g) return;
          shade.pull += (shade.pullT - shade.pull) * 0.08;
          var e = t - shade.tb, burst = e > 0 && e < 2.2 ? Math.sin(Math.PI * Math.min(1, e / 2.2)) * Math.exp(-e * 0.6) : 0;
          var S = H / 2, dt = 0.042;
          for (var p = 0; p < g.P.length; p++) {
            var q = g.P[p];
            q.a += q.w * dt * (1 + 1.4 * shade.pull);
            var r = q.r * (1 - 0.38 * shade.pull) * (1 + 1.6 * burst * (0.6 + q.b));
            for (var k = 0; k < 3; k++) {
              var aa = q.a - k * 0.05 * (1 + shade.pull), x = r * Math.cos(aa), y = r * Math.sin(aa) * K + q.z;
              var rs = Math.sqrt(x * x + y * y);
              if (rs < R && Math.sin(aa) < 0) continue;
              var px = Math.round(shade.cx + x * S), py = Math.round(shade.cy + y * S);
              if (px < 0 || py < 0 || px >= W || py >= H) continue;
              var o = py * W + px, add = q.b * (k === 0 ? 0.75 : 0.32 / k) * (0.6 + 0.6 * (0.5 - 0.5 * Math.cos(aa)));
              buf[o] = Math.min(1, buf[o] + add);
            }
          }
        }
      };
      var init = shade.init;
      shade.init = function (W, H) { var g = init(W, H); shade.g = g; return g; };
      return shade;
    }
  
  function galaxy(o) {
      o = o || {}; var CX = o.cx == null ? 0.5 : o.cx, CY = o.cy == null ? 0.5 : o.cy, SC = o.s || 1, SPIN = o.spin == null ? 0.35 : o.spin;
      return {
        init: function (W, H) {
          var n = W * H, g = { r: new Float32Array(n), th: new Float32Array(n) }, U = Math.min(W, H) / 2 * SC;
          for (var yy = 0, i = 0; yy < H; yy++) for (var xx = 0; xx < W; xx++, i++) {
            var x = (xx - W * CX) / U, y = (yy - H * CY) / U;
            var c = Math.cos(-0.5), s = Math.sin(-0.5), u = x * c - y * s, w = (x * s + y * c) / 0.62;
            g.r[i] = Math.sqrt(u * u + w * w); g.th[i] = Math.atan2(w, u);
          }
          return g;
        },
        at: function (g, i, t) {
          var r = g.r[i]; if (r > 1.05) return 0;
          var arms = Math.pow(0.5 + 0.5 * Math.cos(2 * g.th[i] - 5.2 * Math.log(r + 0.06) - t * SPIN), 3);
          var edge = Math.min(1, (1.05 - r) / 0.35);
          var v = (Math.exp(-r * 2.4) * (0.25 + 1.1 * arms)) * edge + 1.15 * Math.exp(-r * r * 60);
          return v > 1 ? 1 : v;
        }
      };
    }

  window.Ginga = { starfield: starfield, spark: spark, segmented: segmented, pairingCode: pairingCode, reducedMotion: reduce,
    ditherLoop: ditherLoop, blackHole: blackHole, galaxy: galaxy, pixelSky: pixelSky };
})();
