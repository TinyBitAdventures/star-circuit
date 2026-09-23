/* Star Circuit site: starfield + warp, robots, modes, galaxy map, soundtrack. */
(() => {
	'use strict';
	const SC = window.STAR_CIRCUIT || { base: '', data: {} };
	const data = SC.data || {};
	const $ = (s, el = document) => el.querySelector(s);
	const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
	const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

	/* ------------------------------------------------------------ nav */
	const nav = $('#nav');
	const onScroll = () => nav.classList.toggle('scrolled', scrollY > 40);
	addEventListener('scroll', onScroll, { passive: true });
	onScroll();

	/* ------------------------------------------------------------ starfield + warp */
	const sf = $('#starfield');
	const sctx = sf.getContext('2d');
	let W = 0, H = 0, dpr = 1;
	const stars = [];
	let warp = 0, warpTarget = 0;
	const resizeSF = () => {
		dpr = Math.min(devicePixelRatio || 1, 2);
		W = sf.clientWidth; H = sf.clientHeight;
		sf.width = W * dpr; sf.height = H * dpr;
		sctx.setTransform(dpr, 0, 0, dpr, 0, 0);
	};
	for (let i = 0; i < 700; i++) stars.push({ x: (Math.random() - 0.5) * 2, y: (Math.random() - 0.5) * 2, z: Math.random(), h: Math.random() });
	const drawSF = () => {
		warp += (warpTarget - warp) * 0.06;
		const cx = W / 2, cy = H / 2;
		sctx.fillStyle = `rgba(5,6,13,${0.9 - warp * 0.55})`;
		sctx.fillRect(0, 0, W, H);
		// a nebula glow that swells in hyperspace
		const g = sctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(W, H) * 0.6);
		g.addColorStop(0, `rgba(${90 + warp * 60},${80 + warp * 120},255,${0.08 + warp * 0.25})`);
		g.addColorStop(1, 'rgba(0,0,0,0)');
		sctx.fillStyle = g;
		sctx.fillRect(0, 0, W, H);
		const speed = 0.0012 + warp * 0.035;
		for (const s of stars) {
			const pz = s.z;
			s.z -= speed;
			if (s.z <= 0.02) { s.x = (Math.random() - 0.5) * 2; s.y = (Math.random() - 0.5) * 2; s.z = 1; continue; }
			const k = 0.5 / s.z, pk = 0.5 / pz;
			const x = cx + s.x * k * W * 0.5, y = cy + s.y * k * H * 0.5;
			const px = cx + s.x * pk * W * 0.5, py = cy + s.y * pk * H * 0.5;
			if (x < -50 || x > W + 50 || y < -50 || y > H + 50) { s.z = 1; continue; }
			const a = Math.min(1, (1 - s.z) * 1.4);
			const hue = s.h < 0.15 ? '185,140,255' : s.h < 0.3 ? '95,247,255' : '230,240,255';
			sctx.strokeStyle = `rgba(${hue},${a})`;
			sctx.lineWidth = Math.max(0.6, (1 - s.z) * 2.2);
			sctx.beginPath();
			sctx.moveTo(px, py);
			sctx.lineTo(x + (x - px) * warp * 6, y + (y - py) * warp * 6);
			sctx.stroke();
		}
		requestAnimationFrame(drawSF);
	};
	resizeSF();
	addEventListener('resize', resizeSF);
	if (!reduced) requestAnimationFrame(drawSF);
	else { sctx.fillStyle = '#05060d'; sctx.fillRect(0, 0, W, H); }
	const warpBtn = $('#warp-btn');
	const warpOn = (e) => { e.preventDefault(); warpTarget = 1; warpBtn.classList.add('on'); };
	const warpOff = () => { warpTarget = 0; warpBtn.classList.remove('on'); };
	warpBtn.addEventListener('pointerdown', warpOn);
	addEventListener('pointerup', warpOff);
	warpBtn.addEventListener('keydown', (e) => { if (e.key === ' ' || e.key === 'Enter') warpOn(e); });
	warpBtn.addEventListener('keyup', warpOff);

	/* ------------------------------------------------------------ reveal + counters */
	const io = new IntersectionObserver((entries) => {
		for (const en of entries) {
			if (!en.isIntersecting) continue;
			en.target.classList.add('in');
			io.unobserve(en.target);
			if (en.target.classList.contains('stats')) countUp();
		}
	}, { threshold: 0.15 });
	$$('.section-head, .robots, .modes, .galaxy, .player, .game-wrap, .dl-grid, .stats').forEach((el) => { el.classList.add('reveal'); io.observe(el); });
	function countUp() {
		$$('.stat-n').forEach((el) => {
			const to = +el.dataset.count;
			const t0 = performance.now();
			const tick = (t) => {
				const k = Math.min(1, (t - t0) / 1400);
				el.textContent = Math.round(to * (1 - Math.pow(1 - k, 3)));
				if (k < 1) requestAnimationFrame(tick);
			};
			requestAnimationFrame(tick);
		});
	}

	/* ------------------------------------------------------------ robots */
	const robots = data.robots || [];
	const tabs = $('#robot-tabs');
	const img = $('#robot-img');
	robots.forEach((r, i) => {
		const b = document.createElement('button');
		b.type = 'button';
		b.className = 'robot-tab';
		b.setAttribute('role', 'tab');
		b.innerHTML = `<img src="${SC.base}img/robot-${r.id}.jpg" alt=""><strong>${r.name}</strong>`;
		b.addEventListener('click', () => pickRobot(i));
		tabs.appendChild(b);
	});
	function pickRobot(i) {
		const r = robots[i];
		if (!r) return;
		document.documentElement.style.setProperty('--robot', r.color);
		$$('.robot-tab').forEach((t, j) => t.classList.toggle('active', i === j));
		$('#robot-name').textContent = r.name;
		$('#robot-title').textContent = r.title;
		$('#robot-desc').textContent = r.desc;
		$('#robot-ability').textContent = r.ability;
		$('#robot-ability-desc').textContent = r.ability_desc;
		$('#robot-perks').innerHTML = r.perks.filter((p) => !p.startsWith('Ability')).map((p) => `<li>${p}</li>`).join('');
		img.classList.add('swap');
		setTimeout(() => { img.src = `${SC.base}img/robot-${r.id}.jpg`; img.alt = `${r.name}, the ${r.title}`; img.onload = () => img.classList.remove('swap'); }, 180);
	}
	pickRobot(0);

	/* ------------------------------------------------------------ modes */
	$$('.mode-tab').forEach((tab) => tab.addEventListener('click', () => {
		$$('.mode-tab').forEach((t) => t.classList.toggle('active', t === tab));
		$$('.mode').forEach((m) => m.classList.toggle('active', m.dataset.mode === tab.dataset.mode));
	}));
	$$('.mode').forEach((mode) => {
		const shots = $$('.shot', mode);
		const dots = $$('.dot', mode);
		let at = 0;
		const show = (n) => {
			at = (n + shots.length) % shots.length;
			shots.forEach((s, i) => s.classList.toggle('active', i === at));
			dots.forEach((d, i) => d.classList.toggle('active', i === at));
		};
		dots.forEach((d, i) => d.addEventListener('click', () => show(i)));
		if (shots.length > 1) setInterval(() => { if (mode.classList.contains('active') && !document.hidden) show(at + 1); }, 4200);
	});
	const lb = $('#lightbox');
	$$('.shot img').forEach((im) => im.addEventListener('click', () => { $('img', lb).src = im.dataset.full; lb.hidden = false; }));
	lb.addEventListener('click', () => { lb.hidden = true; });
	addEventListener('keydown', (e) => { if (e.key === 'Escape') lb.hidden = true; });

	/* ------------------------------------------------------------ galaxy map */
	const gm = $('#galaxy-map');
	const gctx = gm.getContext('2d');
	const gstars = data.stars || [];
	const biomes = data.biomes || {};
	const card = $('#star-card');
	const WARP_RANGE = 20; // the standard drive; the Void Warp Drive reaches 1.75x
	let routeVoid = false;
	let gW = 0, gH = 0, hover = -1, pinned = -1, routeA = -1, routeB = -1, route = [];
	const bounds = gstars.reduce((b, s) => ({ minx: Math.min(b.minx, s.x), maxx: Math.max(b.maxx, s.x), minz: Math.min(b.minz, s.z), maxz: Math.max(b.maxz, s.z) }), { minx: 1e9, maxx: -1e9, minz: 1e9, maxz: -1e9 });
	const toScreen = (s) => {
		const pad = 60;
		const sx = (gW - pad * 2) / (bounds.maxx - bounds.minx || 1);
		const sz = (gH - pad * 2) / (bounds.maxz - bounds.minz || 1);
		const k = Math.min(sx, sz);
		return [gW / 2 + (s.x - (bounds.minx + bounds.maxx) / 2) * k, gH / 2 + (s.z - (bounds.minz + bounds.maxz) / 2) * k];
	};
	const legendary = (s) => s.planets.some((p) => biomes[p.biome] && biomes[p.biome].legendary);
	const resizeGM = () => {
		const d = Math.min(devicePixelRatio || 1, 2);
		gW = gm.clientWidth; gH = gm.clientHeight;
		gm.width = gW * d; gm.height = gH * d;
		gctx.setTransform(d, 0, 0, d, 0, 0);
	};
	const dist = (a, b) => Math.hypot(gstars[a].x - gstars[b].x, gstars[a].z - gstars[b].z);
	// fewest jumps (each within warp range), breadth first
	function plot(a, b, range = WARP_RANGE) {
		const prev = new Array(gstars.length).fill(-1);
		const seen = new Set([a]);
		const q = [a];
		while (q.length) {
			const c = q.shift();
			if (c === b) break;
			for (let n = 0; n < gstars.length; n++) {
				if (!seen.has(n) && dist(c, n) <= range) { seen.add(n); prev[n] = c; q.push(n); }
			}
		}
		if (!seen.has(b)) return [];
		const path = [b];
		while (path[0] !== a) path.unshift(prev[path[0]]);
		return path;
	}
	let tG = 0;
	const drawGM = () => {
		tG += 0.016;
		gctx.clearRect(0, 0, gW, gH);
		// faint warp lanes between near neighbours
		gctx.lineWidth = 1;
		for (let i = 0; i < gstars.length; i++) {
			for (let j = i + 1; j < gstars.length; j++) {
				if (dist(i, j) <= WARP_RANGE * 0.8) {
					const [ax, ay] = toScreen(gstars[i]), [bx, by] = toScreen(gstars[j]);
					gctx.strokeStyle = 'rgba(95,247,255,0.05)';
					gctx.beginPath(); gctx.moveTo(ax, ay); gctx.lineTo(bx, by); gctx.stroke();
				}
			}
		}
		// the plotted route
		if (route.length > 1) {
			gctx.lineWidth = 3;
			gctx.setLineDash([10, 8]);
			gctx.lineDashOffset = -tG * 30;
			gctx.strokeStyle = routeVoid ? '#ff7ae6' : '#ffd23f';
			gctx.beginPath();
			route.forEach((si, k) => { const [x, y] = toScreen(gstars[si]); k ? gctx.lineTo(x, y) : gctx.moveTo(x, y); });
			gctx.stroke();
			gctx.setLineDash([]);
		}
		gstars.forEach((s, i) => {
			const [x, y] = toScreen(s);
			const r = 3 + s.planets.length * 0.6 + (i === 0 ? 3 : 0);
			const leg = legendary(s);
			const glow = gctx.createRadialGradient(x, y, 0, x, y, r * 5);
			glow.addColorStop(0, s.color + 'aa');
			glow.addColorStop(1, 'rgba(0,0,0,0)');
			gctx.fillStyle = glow;
			gctx.beginPath(); gctx.arc(x, y, r * 5, 0, Math.PI * 2); gctx.fill();
			gctx.fillStyle = s.color;
			gctx.beginPath(); gctx.arc(x, y, r, 0, Math.PI * 2); gctx.fill();
			if (leg || i === 0) {
				gctx.strokeStyle = leg ? '#ffd23f' : '#5ff7ff';
				gctx.lineWidth = 1.5;
				gctx.beginPath(); gctx.arc(x, y, r + 5 + Math.sin(tG * 2 + i) * 1.5, 0, Math.PI * 2); gctx.stroke();
			}
			if (i === hover || i === pinned || i === routeA || i === routeB || i === 0) {
				gctx.font = '600 13px "Exo 2", sans-serif';
				gctx.fillStyle = i === hover || i === pinned ? '#fff' : 'rgba(230,241,255,0.7)';
				gctx.fillText(s.name, x + r + 8, y + 4);
			}
		});
		requestAnimationFrame(drawGM);
	};
	function showStar(i) {
		const s = gstars[i];
		if (!s) return;
		const rows = s.planets.map((p) => {
			const b = biomes[p.biome] || { name: p.biome, color: '#888' };
			const tag = [p.town ? 'town' : '', p.rings ? 'rings' : '', b.legendary ? 'edge world' : ''].filter(Boolean).join(' · ');
			return `<li><span class="chip" style="background:${b.color}"></span>${p.name} <span class="muted">${b.name}</span><span class="tag">${tag}</span></li>`;
		}).join('');
		const extra = [s.moons ? `${s.moons} moon${s.moons > 1 ? 's' : ''}` : '', s.giant ? 'a gas giant' : '', s.station ? s.station : ''].filter(Boolean).join(' · ');
		let routeTxt = '';
		if (routeA >= 0 && routeB >= 0) {
			routeTxt = route.length > 1
				? `<p class="route">Route ${gstars[routeA].name} → ${gstars[routeB].name}: ${route.length - 1} jump${route.length > 2 ? 's' : ''}, ${dist(routeA, routeB).toFixed(1)} ly as the probe flies.${routeVoid ? ' Too far for a standard drive: this route needs the Void Warp Drive.' : ''}</p>`
				: `<p class="route">No route, even with the Void Warp Drive.</p>`;
		} else if (routeA >= 0) {
			routeTxt = `<p class="route">Now click a second star to plot a route from ${gstars[routeA].name}.</p>`;
		}
		card.innerHTML = `<p class="kicker">Class ${s.cls} star${i === 0 ? ' · home' : ''}</p><h3>${s.name}</h3><p class="muted">${s.planets.length} worlds${extra ? ' · ' + extra : ''}</p><ul>${rows}</ul>${routeTxt}`;
	}
	function hit(e) {
		const rect = gm.getBoundingClientRect();
		const mx = e.clientX - rect.left, my = e.clientY - rect.top;
		let best = -1, bd = 22;
		gstars.forEach((s, i) => { const [x, y] = toScreen(s); const d = Math.hypot(x - mx, y - my); if (d < bd) { bd = d; best = i; } });
		return best;
	}
	gm.addEventListener('pointermove', (e) => {
		const h = hit(e);
		if (h !== hover) { hover = h; if (h >= 0) showStar(h); else if (pinned >= 0) showStar(pinned); }
		gm.style.cursor = h >= 0 ? 'pointer' : 'crosshair';
	});
	gm.addEventListener('click', (e) => {
		const h = hit(e);
		if (h < 0) { routeA = routeB = pinned = -1; route = []; return; }
		if (routeA < 0 || routeB >= 0) { routeA = h; routeB = -1; route = []; }
		else if (h !== routeA) {
			routeB = h;
			route = plot(routeA, routeB);
			routeVoid = route.length < 2;
			if (routeVoid) route = plot(routeA, routeB, WARP_RANGE * 1.75);
		}
		pinned = h;
		showStar(h);
	});
	const legend = $('#galaxy-legend');
	legend.innerHTML = '<span><i style="background:#5ff7ff"></i>Home: Solace</span><span><i style="background:#ffd23f"></i>Edge worlds</span><span>Click two stars to plot a route</span>';
	resizeGM();
	addEventListener('resize', resizeGM);
	requestAnimationFrame(drawGM);

	/* ------------------------------------------------------------ soundtrack */
	const audio = new Audio();
	const ext = audio.canPlayType('audio/ogg; codecs="vorbis"') ? '.ogg' : '.m4a';
	audio.preload = 'none';
	audio.crossOrigin = 'anonymous';
	const trackBtns = $$('#tracks button');
	const playBtn = $('#play-btn');
	const seek = $('#seek');
	const vol = $('#vol');
	let current = 0, actx = null, analyser = null, freq = null;
	const fmt = (s) => isFinite(s) ? `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}` : '0:00';
	function load(i, autoplay) {
		current = (i + trackBtns.length) % trackBtns.length;
		const b = trackBtns[current];
		trackBtns.forEach((t) => t.classList.toggle('active', t === b));
		audio.src = b.dataset.src + ext;
		$('#now-title').textContent = $('.t', b).textContent;
		$('#now-desc').textContent = b.dataset.desc;
		if (autoplay) play();
	}
	function ensureAudioGraph() {
		if (actx) return;
		try {
			actx = new (window.AudioContext || window.webkitAudioContext)();
			const src = actx.createMediaElementSource(audio);
			analyser = actx.createAnalyser();
			analyser.fftSize = 256;
			freq = new Uint8Array(analyser.frequencyBinCount);
			src.connect(analyser);
			analyser.connect(actx.destination);
		} catch (err) { actx = null; }
	}
	function play() {
		ensureAudioGraph();
		if (actx && actx.state === 'suspended') actx.resume();
		audio.play().catch(() => {});
	}
	playBtn.addEventListener('click', () => {
		if (!audio.src) load(0, false);
		audio.paused ? play() : audio.pause();
	});
	$('#prev').addEventListener('click', () => load(current - 1, true));
	$('#next').addEventListener('click', () => load(current + 1, true));
	trackBtns.forEach((b, i) => b.addEventListener('click', () => load(i, true)));
	audio.addEventListener('play', () => { playBtn.textContent = '❚❚'; playBtn.setAttribute('aria-label', 'Pause'); });
	audio.addEventListener('pause', () => { playBtn.textContent = '▶'; playBtn.setAttribute('aria-label', 'Play'); });
	audio.addEventListener('ended', () => load(current + 1, true));
	audio.addEventListener('timeupdate', () => {
		if (audio.duration) seek.value = Math.round((audio.currentTime / audio.duration) * 1000);
		$('#time').textContent = fmt(audio.currentTime);
	});
	seek.addEventListener('input', () => { if (audio.duration) audio.currentTime = (seek.value / 1000) * audio.duration; });
	vol.addEventListener('input', () => { audio.volume = vol.value / 100; });
	audio.volume = 0.7;
	load(0, false);
	// the visualiser: a ring of bars around a pulsing core, like the orbit view
	const viz = $('#viz');
	const vctx = viz.getContext('2d');
	const drawViz = () => {
		const d = Math.min(devicePixelRatio || 1, 2);
		const w = viz.clientWidth, h = viz.clientHeight;
		if (viz.width !== w * d) { viz.width = w * d; viz.height = h * d; vctx.setTransform(d, 0, 0, d, 0, 0); }
		vctx.fillStyle = 'rgba(7,10,24,0.35)';
		vctx.fillRect(0, 0, w, h);
		const cx = w * 0.72, cy = h * 0.42, base = Math.min(w, h) * 0.18;
		let level = 0.05;
		if (analyser && !audio.paused) { analyser.getByteFrequencyData(freq); level = freq.reduce((a, b) => a + b, 0) / freq.length / 255; }
		const t = performance.now() / 1000;
		const core = vctx.createRadialGradient(cx, cy, 0, cx, cy, base * (1 + level));
		core.addColorStop(0, 'rgba(255,245,220,0.95)');
		core.addColorStop(0.35, 'rgba(255,170,70,0.7)');
		core.addColorStop(1, 'rgba(120,60,200,0)');
		vctx.fillStyle = core;
		vctx.beginPath(); vctx.arc(cx, cy, base * (1.1 + level), 0, Math.PI * 2); vctx.fill();
		const n = 64;
		for (let i = 0; i < n; i++) {
			const v = freq && !audio.paused ? freq[Math.floor((i / n) * freq.length * 0.8)] / 255 : 0.1 + 0.05 * Math.sin(t * 2 + i);
			const a = (i / n) * Math.PI * 2 + t * 0.1;
			const r1 = base * 1.25, r2 = r1 + 8 + v * base * 1.3;
			vctx.strokeStyle = `hsla(${185 + v * 90},100%,${60 + v * 20}%,${0.35 + v * 0.65})`;
			vctx.lineWidth = 3;
			vctx.beginPath();
			vctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
			vctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2);
			vctx.stroke();
		}
		requestAnimationFrame(drawViz);
	};
	requestAnimationFrame(drawViz);
})();
