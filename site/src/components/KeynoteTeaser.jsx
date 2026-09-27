import React from "react";

/* Teaser do Ginga (GingaKeynote) aberto pelo buraco negro do topo.
   Componente à parte: não mexe no GingaSite gerado. Acha o botão do horizonte (.blast), marca-o com uma dica
   discreta (anel + triângulo de play em CSS) e, no clique, o buraco negro "engole" a página: um disco cosmos
   cresce a partir do horizonte até cobrir a tela, com o anel de fótons acompanhando, e o vídeo começa.
   O vídeo só carrega quando alguém pede. Esc, o botão fechar ou o fim do vídeo devolvem a página. */

const T = {
  pt: { dialog: "Teaser do Ginga", close: "Fechar o teaser", sound: "Ativar som" },
  en: { dialog: "Ginga teaser", close: "Close the teaser", sound: "Turn sound on" },
};
const REVEAL = 900, CLOSE = 750;
/* versão do vídeo no endereço: troque a cada novo render para o navegador não usar o arquivo antigo do cache */
const VIDEO_VERSION = "2026-09-27b";

export default class KeynoteTeaser extends React.Component {
  constructor(p) {
    super(p);
    this.state = { phase: "idle", cx: 0, cy: 0, r0: 60, R: 0, muted: false };
    this.vid = React.createRef(); this.closeBtn = React.createRef();
    this.onBlast = this.onBlast.bind(this); this.onKey = this.onKey.bind(this); this.close = this.close.bind(this);
  }
  componentDidMount() {
    var self = this, tries = 0;
    var find = function () {
      var b = document.querySelector(".hero .blast");
      // espera o GingaSite hidratar o botão, para não brigar com o React dele
      var hydrated = b && Object.keys(b).some(function (k) { return k.indexOf("__reactFiber") === 0 || k.indexOf("__reactProps") === 0; });
      if (!hydrated) { if (tries++ < 100) self._t = setTimeout(find, 100); return; }
      // a dica visual vem só do CSS (teaser.css, texto por :lang); aqui só o clique, sem tocar nos atributos do React
      self.btn = b;
      b.addEventListener("click", self.onBlast);
    };
    find();
  }
  componentWillUnmount() {
    clearTimeout(this._t); (this._timers || []).forEach(clearTimeout);
    if (this.btn) this.btn.removeEventListener("click", this.onBlast);
    document.removeEventListener("keydown", this.onKey);
    document.documentElement.classList.remove("kt-lock");
  }
  /* o site troca PT/EN sem navegar: o aria-label do botão (vindo do React) diz o idioma atual */
  lang() {
    var al = this.btn && this.btn.getAttribute("aria-label");
    if (al) return al.indexOf("Fire") === 0 ? "en" : "pt";
    return this.props.lang === "en" ? "en" : "pt";
  }
  later(fn, ms) { (this._timers = this._timers || []).push(setTimeout(fn, ms)); }
  rm() { try { return window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) { return false; } }

  onBlast() {
    if (this.state.phase !== "idle") return;
    var r = this.btn.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    var W = window.innerWidth, H = window.innerHeight;
    var R = Math.hypot(Math.max(cx, W - cx), Math.max(cy, H - cy)) + 40;
    this.setState({ phase: "start", cx: cx, cy: cy, r0: r.width * 0.4, R: R });
    document.documentElement.classList.add("kt-lock");
    document.addEventListener("keydown", this.onKey);
    // destrava a reprodução com som dentro do próprio gesto de clique (Safari), e começa a baixar
    var v = this.vid.current;
    if (v) { v.muted = false; v.preload = "auto"; var p = v.play(); if (p && p.then) p.then(function () { v.pause(); v.currentTime = 0; }).catch(function () {}); }
    var self = this, rm = this.rm();
    // o estado "start" pinta o círculo no horizonte sem transição; depois de um reflow, "expand" anima até cobrir a tela
    this.later(function () { var el = document.querySelector(".kt-void"); if (el) void el.offsetWidth; self.setState({ phase: "expand" }); }, 30);
    this.later(function () { self.reveal(); }, rm ? 200 : REVEAL);
  }
  reveal() {
    var v = this.vid.current, self = this;
    this.setState({ phase: "play" });
    if (this.closeBtn.current) this.closeBtn.current.focus({ preventScroll: true });
    if (!v) return;
    v.currentTime = 0;
    var p = v.play();
    if (p && p.catch) p.catch(function () { v.muted = true; self.setState({ muted: true }); v.play().catch(function () {}); });
  }
  unmute() { var v = this.vid.current; if (v) { v.muted = false; this.setState({ muted: false }); } }
  onKey(e) { if (e.key === "Escape") this.close(); }
  close() {
    if (this.state.phase === "idle" || this.state.phase === "closing") return;
    var v = this.vid.current, self = this;
    if (v) v.pause();
    (this._timers || []).forEach(clearTimeout); this._timers = [];
    this.setState({ phase: "closing" });
    document.removeEventListener("keydown", this.onKey);
    this.later(function () {
      document.documentElement.classList.remove("kt-lock");
      self.setState({ phase: "idle", muted: false });
      if (self.btn) self.btn.focus({ preventScroll: true });
    }, this.rm() ? 150 : CLOSE);
  }

  render() {
    var s = this.state, L = T[this.lang()], base = this.props.base || "/";
    var open = s.phase !== "idle";
    var grown = s.phase === "expand" || s.phase === "play";
    var r = grown ? s.R : s.r0;
    var cls = "kt kt--" + s.phase;
    var circle = function (rr) { return "circle(" + rr.toFixed(1) + "px at " + s.cx + "px " + s.cy + "px)"; };
    return (
      <div className={cls} role={open ? "dialog" : undefined} aria-modal={open ? "true" : undefined} aria-label={L.dialog} aria-hidden={open ? undefined : "true"}
        >
        {/* halo cobalto e anel de fótons: o mesmo círculo do vazio, um pouco maior, então acompanham a borda exata */}
        <div className="kt-rim kt-rim--halo" style={{ clipPath: circle(r + 16) }} />
        <div className="kt-rim kt-rim--ring" style={{ clipPath: circle(r + 3) }} />
        <div className="kt-void" style={{ clipPath: circle(r) }} />
        <div className="kt-stage">
          <video ref={this.vid} className="kt-video" src={base + "assets/ginga-keynote-" + this.lang() + ".mp4?v=" + VIDEO_VERSION} poster={base + "assets/ginga-keynote-poster.jpg"}
            playsInline preload="none" controls={s.phase === "play"} onEnded={() => this.later(this.close, 500)} tabIndex={open ? 0 : -1} />
          {s.muted && s.phase === "play" && <button className="kt-sound" onClick={() => this.unmute()}>{L.sound}</button>}
        </div>
        <button ref={this.closeBtn} className="kt-close" onClick={this.close} aria-label={L.close} tabIndex={open ? 0 : -1}>
          <svg width="18" height="18" viewBox="0 0 16 16" aria-hidden="true"><path d="M3.5 3.5l9 9M12.5 3.5l-9 9" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" /></svg>
        </button>
      </div>
    );
  }
}
