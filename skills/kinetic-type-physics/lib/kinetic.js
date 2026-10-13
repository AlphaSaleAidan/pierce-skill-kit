/* Deterministic glyph physics. Seconds for moves; milliseconds for stagger. */
(function (root) {
  'use strict';
  const groups = [], NS = 'http://www.w3.org/2000/svg';
  const clamp = x => Math.max(0, Math.min(1, x));
  const random = n => { const x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
  const rest = {x: 0, y: 0, scale: 1, opacity: 1, rotate: 0, spread: 1, blur: 0, smear: 0};
  let filters;
  function pool() {
    if (filters) return;
    const svg = document.createElementNS(NS, 'svg'), defs = document.createElementNS(NS, 'defs');
    svg.setAttribute('width', '0'); svg.setAttribute('height', '0');
    svg.setAttribute('aria-hidden', 'true'); svg.style.position = 'absolute';
    filters = {};
    for (const axis of ['x', 'y']) filters[axis] = Array.from({length: 12}, (_, i) => {
      const f = document.createElementNS(NS, 'filter'), b = document.createElementNS(NS, 'feGaussianBlur');
      f.id = `kinetic-${axis}-${i}`;
      for (const [k, v] of Object.entries({x: '-500%', y: '-500%', width: '1100%', height: '1100%', 'color-interpolation-filters': 'sRGB'})) f.setAttribute(k, v);
      b.setAttribute('stdDeviation', axis === 'x' ? `${i * 48 / 11} 0` : `0 ${i * 48 / 11}`);
      f.append(b); defs.append(f); return f.id;
    });
    svg.append(defs); document.body.append(svg);
  }
  // Closed-form underdamped step with analytic derivative. Damping ratio bounds
  // guarantee 3–5% overshoot. A C1 tail removes the <0.4% residual at dur.
  function response(u, spring = {}, ease) {
    if (u <= 0) return [0, 0];
    if (u >= 1) return [1, 0];
    if (ease === 'out') return [1-Math.pow(1-u,3), 3*Math.pow(1-u,2)];
    if (ease === 'linear') return [u, 1];
    if (ease === 'accelerate') return [u * u, 2 * u];
    if (ease === 'smooth') return [u*u*(3-2*u), 6*u*(1-u)];
    const w = Math.sqrt(spring.stiffness || 144);
    const z = Math.max(.6902, Math.min(.7448, (spring.damping || 16) / (2*w)));
    const a = z*w, b = w*Math.sqrt(1-z*z), e = Math.exp(-a*u);
    let p = 1-e*(Math.cos(b*u)+a/b*Math.sin(b*u));
    let v = e*w*w/b*Math.sin(b*u);
    if (u > .75) {
      const q = (u-.75)/.25, h = q*q*(3-2*q), dh = 6*q*(1-q)/.25;
      v = v*(1-h)+(1-p)*dh; p += (1-p)*h;
    }
    return [p, v];
  }
  function text(el, string, options = {}) {
    pool(); el.replaceChildren(); el.setAttribute('aria-label', string);
    Object.assign(el.style, {position: 'absolute', inset: '0', width: '1600px', height: '900px',
      transform: 'none', opacity: '0', pointerEvents: 'none', overflow: 'visible',
      fontFamily: options.font || 'var(--g-font)', fontWeight: options.weight || 900,
      fontSize: `${options.size || 110}px`, lineHeight: '1', letterSpacing: '0'});
    const group = {el, glyphs: [], script: [], options, layouts: []};
    const lines = Array.isArray(options.rows) ? options.rows : Array(options.rows || 1).fill(string);
    lines.forEach((line, row) => {
      const chars = Array.from(line), spans = chars.map(char => {
        const span = document.createElement('span'); span.className = 'k'; span.textContent = char;
        span.setAttribute('aria-hidden', 'true');
        Object.assign(span.style, {position: 'absolute', whiteSpace: 'pre', transformOrigin: '50% 50%'});
        el.append(span); return span;
      });
      const widths = spans.map(s => s.offsetWidth), tracking = options.tracking || 0;
      const total = widths.reduce((a,b) => a+b, 0)+tracking*(chars.length-1);
      const sx = options.width ? options.width/total : 1;
      let x = (1600-total*sx)/2 + (options.rowOffset?.(row) || 0);
      const rowGlyphs = [];
      spans.forEach((span, col) => {
        const i = group.glyphs.length, width = widths[col];
        const custom = options.layout?.({row, col, i, x, width: width*sx});
        const g = {span, i, row, col, count: chars.length, x: custom?.x ?? x,
          y: custom?.y ?? ((options.top || 0)+row*(options.leading || (options.size || 110)*.85)),
          width, sx, rows: lines.length, size: options.size || 110};
        if (options.color) span.style.color = options.color(g);
        g.echoes = [1,2].map(() => {const copy = span.cloneNode(true); copy.className = 'k-echo'; el.insertBefore(copy, span); return copy;});
        group.glyphs.push(g); rowGlyphs.push(g); x += (width+tracking)*sx;
      });
      group.layouts.push(() => {
        const widths = spans.map(s => s.offsetWidth);
        const total = widths.reduce((a,b) => a+b,0)+tracking*(chars.length-1);
        const sx = options.width ? options.width/total : 1;
        let x = (1600-total*sx)/2 + (options.rowOffset?.(row) || 0);
        rowGlyphs.forEach((g,col) => {
          const custom = options.layout?.({row,col,i:g.i,x,width:widths[col]*sx});
          Object.assign(g,{x:custom?.x ?? x,width:widths[col],sx});
          x += (widths[col]+tracking)*sx;
        });
      });
    });
    group.layouts.push(() => {
      for (let row=0; row<lines.length; row++) {
        const glyphs=group.glyphs.filter(g=>g.row===row);
        const left=Math.min(...glyphs.map(g=>g.x));
        const right=Math.max(...glyphs.map(g=>g.x+g.width*g.sx));
        glyphs.forEach(g=>Object.assign(g,{rowLeft:left,rowCentre:(left+right)/2}));
      }
    });
    group.layouts.at(-1)();
    groups.push(group); return group;
  }
  function delay(g, s = {}) {
    let rank = g.col;
    if (s.order === 'rtl') rank = g.count-1-g.col;
    if (s.order === 'center') rank = Math.abs(g.col-(g.count-1)/2);
    if (s.order === 'random') rank = random(g.i+17)*(g.count-1);
    if (s.steps) rank = Math.floor(rank*(s.steps-1)/Math.max(1,g.count-1));
    let row = g.row;
    if (s.rowOrder === 'bottom') row = g.rows-1-g.row;
    if (s.rowOrder === 'center') row = Math.abs(g.row-(g.rows-1)/2);
    return (rank*(s.letter || 0)+row*(s.row || 0))/1000;
  }
  const resolve = (value, g) => typeof value === 'function' ? value(g) : value;
  function play(group, script) {
    group.script = script.flat(Infinity).map(m => {
      const delays = group.glyphs.map(g => delay(g, m.stagger));
      const max = Math.max(0, ...delays), budget = m.exactStagger || m.window == null ? max : Math.max(0, m.window-m.dur);
      return {...m, delays: delays.map(d => max ? d*Math.min(1,budget/max) : 0)};
    });
    return group;
  }
  function sample(group, g, t, reduced = false) {
    if (reduced) {
      const start = group.start ?? Math.min(...group.script.flat(Infinity).map(m => m.at));
      return {state:{...rest,opacity:Number(t >= start && t < (group.end ?? Infinity))},
        velocity:{x:0,y:0,scale:0,rotate:0,spread:0}};
    }
    let state = {...rest, opacity: 0}, velocity = {x:0,y:0,scale:0,rotate:0,spread:0};
    for (const m of group.script) {
      if (m.select && !m.select(g)) continue;
      const start = m.at+m.delays[g.i];
      if (t < start) continue;
      const from = {...state, ...resolve(m.from, g)}, to = {...from, ...resolve(m.to, g)};
      const [p, dp] = response((t-start)/m.dur, m.spring, m.ease);
      if (m.anchor) state.anchor = m.anchor;
      const channels = new Set([...Object.keys(resolve(m.from,g) || {}), ...Object.keys(resolve(m.to,g) || {})]);
      for (const k of channels) {
        state[k] = from[k]+(to[k]-from[k])*p;
        if (k in velocity) velocity[k] = (to[k]-from[k])*dp/m.dur;
      }
      if (m.blur === false) velocity = {x:0,y:0,scale:0,rotate:0,spread:0};
    }
    return {state, velocity};
  }
  function update(t, reduced = false) {
    for (const group of groups) {
      const on = t >= (group.start ?? -Infinity) && t < (group.end ?? Infinity);
      group.el.style.opacity = on ? 1 : 0;
      const post = !reduced && group.post ? group.post(t) : {};
      group.el.style.transform = `translate(${post.x || 0}px,${post.y || 0}px) scale(${post.scale ?? 1})`;
      group.el.style.filter = post.blur ? `blur(${post.blur}px)` : 'none';
      for (const g of group.glyphs) {
        const {state:s, velocity:v} = sample(group, g, t, reduced);
        // Scale/rotation velocity contributes edge displacement, even at the pivot.
        const pivot = s.anchor === 'left' ? g.rowLeft : g.rowCentre;
        const radius = g.x+g.width*g.sx/2-pivot;
        const trackRadius = g.x+g.width*g.sx/2-g.rowCentre;
        const vx = v.x+v.scale*radius+v.spread*trackRadius+s.smear/.04, vy = v.y+v.rotate*Math.PI/180*g.size*.5;
        const axis = Math.abs(vx) >= Math.abs(vy) ? 'x' : 'y';
        const speed = Math.hypot(vx,vy), level = Math.min(11, Math.round(Math.max(s.blur,speed*.004)*11/48));
        const filter = reduced || !level ? 'none' : `url(#${filters[axis][level]})`;
        const paint = (node, dt, alpha) => {
          node.style.left = `${g.x+(g.sx-1)*g.width/2}px`; node.style.top = `${g.y}px`;
          node.style.transform = `translate(${s.x+(s.scale-1)*radius+(s.spread-1)*trackRadius-vx*dt}px,${s.y-v.y*dt}px) rotate(${s.rotate-v.rotate*dt}deg) scale(${Math.max(.01,s.scale-v.scale*dt)}) scaleX(${g.sx})`;
          node.style.opacity = clamp(s.opacity)*alpha; node.style.filter = filter;
        };
        paint(g.span, 0, 1);
        g.echoes.forEach((node,i) => paint(node, (i+1)/25, reduced ? 0 : clamp(speed/1800)*(.36-i*.06)));
      }
    }
  }
  const move = (from, to, o = {}) => ({at:0, dur:.18, stagger:{letter:10,row:45,order:'ltr'}, blur:'auto', from, to, ...o});
  // Catalogue moves compose only their declared channels; arrays are flattened by play.
  const exact = {stagger:{}, exactStagger:true};
  const fx = (from,to,o={}) => move(from,to,{...exact,...o});
  const presets = {
    wordZoomSettle(o={}) {return fx({scale:3,opacity:1},{scale:1},{dur:.16,ease:'out',...o});},
    // Call on the complete line: prefix re-centres as the new suffix arrives.
    wordAppend(edge, o={}) {
      const {at=0,dur=.16,...other}=o;
      const shift=g=>(g.rowCentre-g.rowLeft)*(g.count-edge)/g.count;
      return [fx(g=>({x:shift(g)}),{x:0},{at,dur,ease:'out',select:g=>g.col<edge,...other}),
        fx(g=>({x:1700-g.x,opacity:1}),{x:0},{at,dur,ease:'out',select:g=>g.col>=edge,...other})];
    },
    smearDissolve(o={}) {return fx({x:0,blur:0,opacity:1},{x:40,blur:30,opacity:0},{dur:.12,ease:'linear',...o});},
    letterPour(o={}) {return fx(g=>({x:1700-g.x,opacity:1}),{x:0},{dur:.16,stagger:{letter:40,row:60,rowOrder:'center'},...o});},
    letterEat(o={}) {return fx({x:0,opacity:1,blur:0,smear:0},{x:0,opacity:0,blur:30,smear:60},{dur:.08,ease:'linear',stagger:{letter:40,row:80,rowOrder:'center'},...o});},
    letterEatFast(o={}) {return presets.letterEat({stagger:{letter:20},...o});},
    scatterPop(o={}) {return fx({opacity:0,blur:8,scale:1.1},{opacity:1,blur:0,scale:1},{dur:.08,stagger:{letter:20,order:'random'},...o});},
    trackCollapse(spread=1.6,o={}) {return fx({spread},{spread:1},{dur:.16,spring:{damping:17.8},...o});},
    stackBloom(o={}) {return fx(g=>({y:((g.rows-1)/2-g.row)*g.size*.85,scale:.9,spread:1.1,opacity:1}),
      {y:0,scale:1,spread:1,opacity:1},{dur:.16,stagger:{row:40,rowOrder:'center'},...o});},
    giantRowSettle(o={}) {return fx(g=>({x:(g.row%2?-1:1)*400,scale:3,opacity:1}),{x:0,scale:1},{dur:.24,ease:'out',stagger:{row:80},...o});},
    rowLiftOff(o={}) {return fx({y:0,opacity:1},g=>({y:-300,opacity:0}),{dur:.12,ease:'accelerate',stagger:{row:100},...o});},
    rowSlideAlt(o={}) {
      const {at=0,...other}=o, sign=g=>g.row<Math.ceil(g.rows/2)?-1:1;
      return [fx(g=>({x:sign(g)*1700,opacity:1}),g=>({x:sign(g)*24}),{at,dur:.2,stagger:{row:80},...other}),
        presets.realign({at:at+.2,...other})];
    },
    realign(o={}) {return fx(g=>({x:(g.row<Math.ceil(g.rows/2)?-1:1)*24}),{x:0},{dur:.1,stagger:{row:80},...o});},
    breathe(at,dur=.5,amount=.15) {return t=>({scale:1+amount*clamp((t-at)/dur)});},
    // Pure container helper: 3 frames up, cut at `cut`, 3 frames down.
    defocusWhip(cut,dur=.12,blur=40) {return t=>({blur:t<cut?blur*clamp((t-cut+dur)/dur):blur*(1-clamp((t-cut)/dur))});},
    pillPop(o={}) {const {sub=false,...timing}=o;return fx(sub?{y:-24,opacity:0}:{scale:1.15,opacity:0,blur:20},
      sub?{y:0,opacity:1}:{scale:1,opacity:1,blur:0},{dur:sub?.16:.12,ease:'out',...timing});},
    wordMaterialize(o={}) {return fx({opacity:0,blur:12,scale:1.05},{opacity:1,blur:0,scale:1},{dur:.16,ease:'out',...o});},
    giantFlyThrough(o={}) {return fx({x:1300,scale:5,blur:30,opacity:1},{x:-900,scale:2.5,blur:0,opacity:0},{dur:.28,ease:'out',...o});},
    stackMultiply(o={}) {
      const {at=0,...other}=o;
      return [fx(g=>({x:1700-g.x,y:((g.rows-1)/2-g.row)*g.size,opacity:1,scale:1.15}),
        {x:0,y:0},{at,dur:.16,stagger:{letter:10},...other}),
        presets.trackCollapse(2,{at,dur:.28,...other}),
        fx({scale:1.15},{scale:1},{at:at+.28,dur:.2,...other})];
    },
    peelCountdown(o={}) {
      const {at=0,steps,...other}=o, middle=g=>g.row===Math.floor(g.rows/2);
      return [fx({y:0,opacity:1},g=>({y:g.row<g.rows/2?-300:300,opacity:0}),{at,dur:.12,select:g=>!middle(g),...other}),
        fx({scale:1},{scale:1.6},{at,dur:.56,anchor:'left',select:middle,...other}),
        fx({opacity:1,blur:0},{opacity:0,blur:12},{at,dur:.08,stagger:{letter:100,order:'rtl',steps},select:middle,...other})];
    },
    gridCascade(o={}) {return fx({x:600,opacity:1},{x:0},{dur:.2,stagger:{letter:50,row:50,rowOrder:'center'},...o});},
    pourIn(dir = 'rtl', o = {}) {
      return move(g => ({x:dir === 'rtl' ? 1700-g.x : -1700-g.x, opacity:0}), rest, o);
    },
    eatOut(dir = 'ltr', o = {}) {
      return move(rest, g => ({x:(dir === 'ltr' ? -1 : 1)*(450+(g.row%2)*90),opacity:0}),
        {ease:'accelerate',stagger:{letter:12,row:45,order:dir},...o});
    },
    splitOut(parts = ['SPLIT','WORD'], o = {}) {
      const edge = parts[0].length;
      return move(rest, g => ({x:g.col < edge ? -120 : 1700, opacity:0}),
        {ease:'accelerate',stagger:{letter:9,row:0,order:'rtl'},...o});
    },
    zoomSettle(scale = 2.5, o = {}) {
      const {giant = false, ...timing} = o;
      return move(g => ({scale, x:giant ? 800-g.x-g.width/2 : 0,
        y:giant ? 450-g.y-g.size/2 : 0, opacity:0}), rest, timing);
    },
    cascade(grid = [5,4], wave = 'rtl', o = {}) {
      return move({x:1500,opacity:0}, rest, {stagger:{letter:55,row:22,order:wave},...o});
    },
    scatterSettle(jitter = 40, o = {}) {
      return move(g => ({x:(random(g.i+1)-.5)*jitter*2,y:(random(g.i+9)-.5)*jitter,
        rotate:(random(g.i+23)-.5)*12,scale:1.08,opacity:0}), rest,
        {stagger:{letter:10,row:45,order:'random'},...o});
    },
    burstOut(radial = 1800, o = {}) {
      return move(rest, g => {const a=Math.atan2(g.y+g.size/2-450,g.x+g.width/2-800);
        return {x:Math.cos(a)*radial,y:Math.sin(a)*radial,rotate:(random(g.i)-.5)*30,scale:1.6,opacity:0};},
        {dur:2/30,ease:'accelerate',stagger:{},...o});
    },
    wipeRows(dir = 'alternate', o = {}) {
      return move(rest, g => ({y:dir === 'up' ? -1000 : 0,
        x:dir === 'up' ? 0 : (dir === 'alternate' ? (g.row%2 ? 1 : -1) : dir === 'ltr' ? 1 : -1)*1700,opacity:0}),
        {ease:'accelerate',stagger:{letter:0,row:45},...o});
    }
  };
  root.Kinetic = {text, play, update, sample, response, presets, overlap:.15, groups,
    reflow: () => groups.forEach(g => g.layouts.forEach(layout => layout()))};
})(window);
