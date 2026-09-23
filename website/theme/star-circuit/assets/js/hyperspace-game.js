/* Hyperspace Run: a browser-sized take on Star Circuit's pirate interdiction.
   A perspective tunnel (world units: the tunnel has radius 1, depth z grows
   away from the camera). You fly at a fixed depth, move with the pointer or
   arrow keys, and fire straight down the tunnel. Survive 60 seconds. */
(() => {
	'use strict';
	const cv = document.getElementById('hyper-game');
	if (!cv) return;
	const ctx = cv.getContext('2d');
	const overlay = document.getElementById('game-overlay');
	const startBtn = document.getElementById('game-start');
	const bestEl = document.getElementById('game-best');
	const W = cv.width, H = cv.height, CX = W / 2, CY = H / 2;
	const F = H * 0.36; // focal length
	const PZ = 0.35; // the player's depth
	const PR = 0.72; // how far from the axis you can fly
	const DURATION = 60;
	const read = (k) => { try { return +localStorage.getItem(k) || 0; } catch (e) { return 0; } };
	const write = (k, v) => { try { localStorage.setItem(k, String(v)); } catch (e) { /* private mode */ } };

	let state = 'menu';
	let t = 0, last = 0, hull = 100, score = 0, kills = 0, fireCd = 0, shake = 0, flash = 0;
	let px = 0, py = 0.2, tx = 0, ty = 0.2, firing = false;
	let enemies = [], shots = [], bolts = [], sparks = [], rings = [], waves = [];
	const keys = {};

	const proj = (x, y, z) => [CX + (x * F) / z, CY + (y * F) / z, F / z];
	for (let i = 0; i < 26; i++) rings.push({ z: 0.3 + i * 0.12, h: Math.random() });

	function reset() {
		t = 0; hull = 100; score = 0; kills = 0; fireCd = 0; shake = 0; flash = 0;
		px = 0; py = 0.2; tx = px; ty = py;
		enemies = []; shots = []; bolts = []; sparks = [];
		waves = [[2, 'swarm', 3], [8, 'raider', 2], [15, 'mine', 5], [21, 'swarm', 4], [27, 'raider', 3], [34, 'mine', 6], [36, 'swarm', 3], [43, 'raider', 4], [51, 'swarm', 6], [52, 'mine', 4]];
	}

	function spawn(kind, n) {
		for (let i = 0; i < n; i++) {
			const a = Math.random() * Math.PI * 2, r = Math.random() * 0.6;
			if (kind === 'raider') enemies.push({ kind, x: Math.cos(a) * r, y: Math.sin(a) * r * 0.7, z: 4 + i * 0.4, st: 1.1 + Math.random() * 0.6, hp: 3, cd: 1 + Math.random() * 1.5, ph: Math.random() * 9 });
			else if (kind === 'swarm') enemies.push({ kind, x: Math.cos(a) * r, y: Math.sin(a) * r, z: 3.5 + i * 0.25, hp: 1, cd: 1.5 + Math.random() * 2.5, dive: false, ph: Math.random() * 9 });
			else enemies.push({ kind, x: (Math.random() - 0.5) * 1.3, y: (Math.random() - 0.5) * 1.1, z: 3.2 + i * 0.5, hp: 2, ph: Math.random() * 9 });
		}
	}

	function burst(x, y, z, col, n) {
		for (let i = 0; i < n; i++) {
			const a = Math.random() * Math.PI * 2, s = 0.2 + Math.random() * 0.6;
			sparks.push({ x, y, z, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.5 + Math.random() * 0.4, col });
		}
	}

	function hurt(d) {
		hull -= d;
		shake = Math.min(1, shake + 0.5);
		flash = 0.5;
		if (hull <= 0) end(false);
	}

	function end(won) {
		state = 'over';
		if (won) score += Math.max(0, Math.round(hull)) * 10 + 500;
		const best = Math.max(read('sc-hyper-best'), score);
		write('sc-hyper-best', best);
		overlay.hidden = false;
		overlay.querySelector('h3').textContent = won ? 'Escaped!' : 'Knocked out of hyperspace';
		overlay.querySelector('p').textContent = `${kills} pirates down · score ${score.toLocaleString()}`;
		startBtn.textContent = 'Fly again';
		bestEl.textContent = `Best: ${best.toLocaleString()}`;
	}

	function update(dt) {
		t += dt;
		// steering: pointer target, or arrow keys nudging it
		const kx = (keys.ArrowRight || keys.d ? 1 : 0) - (keys.ArrowLeft || keys.a ? 1 : 0);
		const ky = (keys.ArrowDown || keys.s ? 1 : 0) - (keys.ArrowUp || keys.w ? 1 : 0);
		if (kx || ky) { tx += kx * dt * 1.6; ty += ky * dt * 1.6; }
		const tl = Math.hypot(tx, ty);
		if (tl > PR) { tx *= PR / tl; ty *= PR / tl; }
		px += (tx - px) * Math.min(1, dt * 9);
		py += (ty - py) * Math.min(1, dt * 9);
		for (const r of rings) { r.z -= dt * 1.6; if (r.z < 0.25) { r.z += 26 * 0.12; r.h = Math.random(); } }
		waves = waves.filter((w) => { if (t >= w[0]) { spawn(w[1], w[2]); return false; } return true; });
		// firing
		fireCd -= dt;
		if ((firing || keys[' ']) && fireCd <= 0) {
			fireCd = 0.13;
			shots.push({ x: px - 0.05, y: py, z: PZ + 0.02 }, { x: px + 0.05, y: py, z: PZ + 0.02 });
		}
		for (const s of shots) s.z += dt * 5;
		shots = shots.filter((s) => s.z < 5);
		// enemies
		for (const e of enemies) {
			e.ph += dt;
			if (e.kind === 'raider') {
				e.z += (e.st - e.z) * Math.min(1, dt * 1.2);
				e.x += Math.sin(e.ph * 1.3) * dt * 0.25;
				e.y += Math.cos(e.ph * 1.7) * dt * 0.18;
				e.cd -= dt;
				if (e.cd <= 0 && Math.abs(e.z - e.st) < 0.2) {
					e.cd = 1.4 + Math.random() * 1.2;
					const dx = px - e.x, dy = py - e.y, dz = PZ - e.z, L = Math.hypot(dx, dy, dz);
					bolts.push({ x: e.x, y: e.y, z: e.z, vx: (dx / L) * 1.3, vy: (dy / L) * 1.3, vz: (dz / L) * 1.3 });
				}
			} else if (e.kind === 'swarm') {
				if (!e.dive) {
					e.z += (1.6 - e.z) * Math.min(1, dt * 1.5);
					e.x += Math.sin(e.ph * 2.3) * dt * 0.4;
					e.cd -= dt;
					if (e.cd <= 0) { e.dive = true; e.tx = px; e.ty = py; }
				} else {
					const dx = e.tx - e.x, dy = e.ty - e.y, dz = PZ - e.z, L = Math.hypot(dx, dy, dz) || 1;
					e.x += (dx / L) * dt * 1.4; e.y += (dy / L) * dt * 1.4; e.z += (dz / L) * dt * 1.4;
					if (e.z < PZ + 0.04) {
						if (Math.hypot(e.x - px, e.y - py) < 0.16) { hurt(14); e.hp = 0; burst(e.x, e.y, e.z, '255,140,60', 16); }
						else { e.z = 3.2; e.dive = false; e.cd = 2 + Math.random() * 2; }
					}
				}
			} else {
				e.z -= dt * 0.7;
				if (e.z < PZ + 0.04) {
					if (Math.hypot(e.x - px, e.y - py) < 0.2) { hurt(20); burst(e.x, e.y, e.z, '255,90,60', 22); }
					e.hp = 0; e.silent = true;
				}
			}
			for (const s of shots) {
				const rad = e.kind === 'raider' ? 0.16 : e.kind === 'mine' ? 0.12 : 0.1;
				if (!s.hit && Math.abs(s.z - e.z) < 0.12 && Math.hypot(s.x - e.x, s.y - e.y) < rad) {
					s.hit = true; e.hp -= 1;
					burst(e.x, e.y, e.z, '255,220,140', 4);
				}
			}
		}
		shots = shots.filter((s) => !s.hit);
		for (const e of enemies) {
			if (e.hp <= 0 && !e.dead) {
				e.dead = true;
				if (!e.silent) {
					kills += 1;
					score += e.kind === 'raider' ? 250 : e.kind === 'mine' ? 80 : 120;
					burst(e.x, e.y, e.z, e.kind === 'raider' ? '255,80,90' : '255,160,60', 20);
					shake = Math.min(1, shake + 0.15);
				}
			}
		}
		enemies = enemies.filter((e) => !e.dead);
		for (const b of bolts) {
			b.x += b.vx * dt; b.y += b.vy * dt; b.z += b.vz * dt;
			if (b.z < PZ + 0.03) {
				if (Math.hypot(b.x - px, b.y - py) < 0.1) hurt(7);
				b.gone = true;
			}
		}
		bolts = bolts.filter((b) => !b.gone);
		for (const p of sparks) { p.x += p.vx * dt * 0.3; p.y += p.vy * dt * 0.3; p.life -= dt; }
		sparks = sparks.filter((p) => p.life > 0);
		shake = Math.max(0, shake - dt * 2);
		flash = Math.max(0, flash - dt * 2);
		score += Math.round(dt * 10);
		if (t >= DURATION) end(true);
	}

	function draw() {
		const sx = (Math.random() - 0.5) * shake * 14, sy = (Math.random() - 0.5) * shake * 14;
		ctx.setTransform(1, 0, 0, 1, sx, sy);
		const alarm = state === 'play' && enemies.length ? 0.5 + 0.5 * Math.sin(t * 6) : 0;
		const bg = ctx.createRadialGradient(CX, CY, 0, CX, CY, W * 0.7);
		bg.addColorStop(0, '#eaf6ff');
		bg.addColorStop(0.08, `rgb(${120 + alarm * 80},${110 - alarm * 40},255)`);
		bg.addColorStop(0.45, `rgb(${40 + alarm * 60},${20},${110 - alarm * 40})`);
		bg.addColorStop(1, '#05030f');
		ctx.fillStyle = bg;
		ctx.fillRect(-20, -20, W + 40, H + 40);
		// tunnel rings and light streaks racing toward you
		rings.sort((a, b) => b.z - a.z);
		for (const r of rings) {
			const [, , s] = proj(1, 0, r.z);
			const a = Math.min(1, (3.2 - r.z) / 2.5) * 0.5;
			ctx.strokeStyle = r.h < 0.3 ? `rgba(95,247,255,${a})` : `rgba(185,140,255,${a})`;
			ctx.lineWidth = Math.max(1, s * 0.012);
			ctx.beginPath(); ctx.arc(CX, CY, s, 0, Math.PI * 2); ctx.stroke();
		}
		for (let i = 0; i < 40; i++) {
			const ang = i * 2.399 + t * 0.05;
			const z1 = ((i * 0.37 - t * 2.2) % 3 + 3) % 3 + 0.25;
			const [x1, y1] = proj(Math.cos(ang), Math.sin(ang), z1);
			const [x2, y2] = proj(Math.cos(ang), Math.sin(ang), z1 + 0.35);
			ctx.strokeStyle = 'rgba(220,240,255,0.35)';
			ctx.lineWidth = 2;
			ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
		}
		// far to near: enemies, bolts, sparks
		const things = [
			...enemies.map((e) => ({ z: e.z, draw: () => drawEnemy(e) })),
			...bolts.map((b) => ({ z: b.z, draw: () => { const [x, y, s] = proj(b.x, b.y, b.z); glowDot(x, y, s * 0.04, '255,70,90'); } })),
			...shots.map((b) => ({ z: b.z, draw: () => { const [x, y, s] = proj(b.x, b.y, b.z); const [x2, y2] = proj(b.x, b.y, b.z + 0.15); ctx.strokeStyle = 'rgba(140,250,255,0.95)'; ctx.lineWidth = Math.max(1.5, s * 0.02); ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x2, y2); ctx.stroke(); } })),
			...sparks.map((p) => ({ z: p.z, draw: () => { const [x, y, s] = proj(p.x, p.y, p.z); ctx.fillStyle = `rgba(${p.col},${p.life * 1.6})`; ctx.fillRect(x, y, Math.max(2, s * 0.012), Math.max(2, s * 0.012)); } })),
		].sort((a, b) => b.z - a.z);
		for (const th of things) if (th.z > PZ - 0.05) th.draw();
		if (state !== 'menu') drawPlayer();
		for (const th of things) if (th.z <= PZ - 0.05) th.draw();
		ctx.setTransform(1, 0, 0, 1, 0, 0);
		if (flash > 0) { ctx.fillStyle = `rgba(255,60,60,${flash * 0.35})`; ctx.fillRect(0, 0, W, H); }
		if (state === 'play') drawHud();
	}

	function glowDot(x, y, r, col) {
		const g = ctx.createRadialGradient(x, y, 0, x, y, r * 3);
		g.addColorStop(0, `rgba(255,255,255,0.95)`);
		g.addColorStop(0.3, `rgba(${col},0.9)`);
		g.addColorStop(1, `rgba(${col},0)`);
		ctx.fillStyle = g;
		ctx.beginPath(); ctx.arc(x, y, r * 3, 0, Math.PI * 2); ctx.fill();
	}

	function drawEnemy(e) {
		const [x, y, s] = proj(e.x, e.y, e.z);
		const k = s * 0.001;
		ctx.save();
		ctx.translate(x, y);
		if (e.kind === 'raider') {
			ctx.rotate(Math.sin(e.ph * 1.1) * 0.3);
			ctx.fillStyle = '#2a1e2e';
			ctx.beginPath(); ctx.moveTo(0, -60 * k); ctx.lineTo(70 * k, 30 * k); ctx.lineTo(0, 12 * k); ctx.lineTo(-70 * k, 30 * k); ctx.closePath(); ctx.fill();
			ctx.strokeStyle = '#ff5a6a'; ctx.lineWidth = Math.max(1, 5 * k); ctx.stroke();
			glowDot(0, -8 * k, 10 * k, '255,80,90');
		} else if (e.kind === 'swarm') {
			const warn = !e.dive && e.cd < 0.7 ? (Math.sin(e.ph * 30) > 0 ? 1 : 0.4) : 1;
			ctx.rotate(e.ph * 3);
			ctx.fillStyle = e.dive ? '#ffb347' : '#c9722a';
			ctx.beginPath(); ctx.moveTo(0, -34 * k); ctx.lineTo(26 * k, 0); ctx.lineTo(0, 34 * k); ctx.lineTo(-26 * k, 0); ctx.closePath(); ctx.fill();
			glowDot(0, 0, 9 * k * warn, '255,160,60');
		} else {
			ctx.rotate(e.ph);
			ctx.strokeStyle = '#8a2a2a'; ctx.lineWidth = Math.max(1, 6 * k);
			for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.cos(a) * 48 * k, Math.sin(a) * 48 * k); ctx.stroke(); }
			ctx.fillStyle = '#2a2530'; ctx.beginPath(); ctx.arc(0, 0, 32 * k, 0, Math.PI * 2); ctx.fill();
			glowDot(0, 0, 8 * k * (0.7 + 0.3 * Math.sin(t * 8)), '255,70,50');
		}
		ctx.restore();
	}

	function drawPlayer() {
		const [x, y, s] = proj(px, py, PZ);
		const k = s * 0.0012;
		const bank = (tx - px) * 3;
		ctx.save();
		ctx.translate(x, y);
		ctx.rotate(bank * 0.4);
		// thruster flames
		for (const off of [-22, 22]) glowDot(off * k, 26 * k, 7 * k * (0.8 + 0.3 * Math.random()), '95,247,255');
		ctx.fillStyle = '#e6e8ec';
		ctx.beginPath(); ctx.moveTo(0, -40 * k); ctx.lineTo(44 * k, 24 * k); ctx.lineTo(0, 12 * k); ctx.lineTo(-44 * k, 24 * k); ctx.closePath(); ctx.fill();
		ctx.fillStyle = '#18c2b0';
		ctx.beginPath(); ctx.moveTo(0, -24 * k); ctx.lineTo(12 * k, 6 * k); ctx.lineTo(-12 * k, 6 * k); ctx.closePath(); ctx.fill();
		ctx.restore();
		// crosshair far down the tunnel, where your shots land
		const [ax, ay] = proj(px, py, 1.4);
		ctx.strokeStyle = 'rgba(160,240,255,0.8)';
		ctx.lineWidth = 2;
		ctx.beginPath(); ctx.arc(ax, ay, 10, 0, Math.PI * 2); ctx.stroke();
		ctx.beginPath(); ctx.moveTo(ax - 16, ay); ctx.lineTo(ax - 6, ay); ctx.moveTo(ax + 6, ay); ctx.lineTo(ax + 16, ay); ctx.stroke();
	}

	function drawHud() {
		ctx.font = '600 16px "Orbitron", sans-serif';
		ctx.fillStyle = '#e6f1ff';
		ctx.fillText(`SCORE ${score.toLocaleString()}`, 24, 36);
		ctx.textAlign = 'right';
		ctx.fillText(`${Math.max(0, Math.ceil(DURATION - t))}s`, W - 24, 36);
		ctx.textAlign = 'left';
		ctx.fillStyle = 'rgba(255,255,255,0.15)'; ctx.fillRect(24, H - 34, 200, 10);
		ctx.fillStyle = hull > 40 ? '#6ee06a' : '#ff5a5a'; ctx.fillRect(24, H - 34, 2 * Math.max(0, hull), 10);
		ctx.font = '600 11px "Orbitron", sans-serif';
		ctx.fillStyle = '#8ea3bf'; ctx.fillText('HULL', 24, H - 42);
		ctx.fillStyle = 'rgba(255,255,255,0.15)'; ctx.fillRect(W / 2 - 200, 20, 400, 6);
		ctx.fillStyle = '#5ff7ff'; ctx.fillRect(W / 2 - 200, 20, 400 * Math.min(1, t / DURATION), 6);
	}

	function frame(now) {
		const dt = Math.min(0.05, (now - last) / 1000 || 0);
		last = now;
		if (state === 'play') update(dt);
		else for (const r of rings) { r.z -= dt * 0.6; if (r.z < 0.25) r.z += 26 * 0.12; }
		draw();
		requestAnimationFrame(frame);
	}

	// input
	const toWorld = (e) => {
		const r = cv.getBoundingClientRect();
		const mx = ((e.clientX - r.left) / r.width) * W, my = ((e.clientY - r.top) / r.height) * H;
		tx = ((mx - CX) * PZ) / F; ty = ((my - CY) * PZ) / F;
	};
	cv.addEventListener('pointermove', (e) => { if (state === 'play') toWorld(e); });
	cv.addEventListener('pointerdown', (e) => { if (state === 'play') { toWorld(e); firing = true; cv.setPointerCapture(e.pointerId); } });
	cv.addEventListener('pointerup', () => { firing = false; });
	cv.addEventListener('pointercancel', () => { firing = false; });
	addEventListener('keydown', (e) => {
		if (state !== 'play') return;
		keys[e.key] = true;
		if (e.key === ' ' || e.key.startsWith('Arrow')) e.preventDefault();
	});
	addEventListener('keyup', (e) => { keys[e.key] = false; });
	startBtn.addEventListener('click', () => { reset(); state = 'play'; overlay.hidden = true; });
	const best = read('sc-hyper-best');
	if (best) bestEl.textContent = `Best: ${best.toLocaleString()}`;
	requestAnimationFrame(frame);
})();
