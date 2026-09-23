<?php
/**
 * The one page: everything about Star Circuit, interactive.
 */

defined( 'ABSPATH' ) || exit;

$data     = star_circuit_data();
$counts   = $data['counts'] ?? [];
$version  = $data['version'] ?? '0.2.0';
$img      = get_template_directory_uri() . '/assets/img/';
$release  = 'https://github.com/austinginder/star-circuit/releases/latest';
$repo     = 'https://github.com/austinginder/star-circuit';

$modes = [
	[
		'id'    => 'planets',
		'name'  => 'Walk the worlds',
		'kicker'=> 'Spherical planets',
		'text'  => 'Every world is a small sphere you can walk all the way around, with a day and night cycle, weather, oceans, flora and wandering creatures. Gather resources, scan species, fight rogue drones and trade in towns.',
		'bullets' => [ 'Nine world types, from verdant meadows to crystal plains', 'Mining, botany and siphoning with WoW-style professions', 'Towns with merchants, trainers and bounty boards' ],
		'shots' => [ [ 'planet-dusk', 'Dusk at the Cradle outpost' ], [ 'planet-desert', 'Noon on an arid world' ], [ 'planet-crystal', 'Sunset over a crystalline world' ], [ 'mining', 'Cutting ore with the mining laser' ] ],
	],
	[
		'id'    => 'orbit',
		'name'  => 'Probe the core',
		'kicker'=> 'Orbit mode',
		'text'  => 'Hold orbit over any planet, moon or gas giant and the world is cut open beneath you. Drop a tethered probe past faultstone and molten heat to pull out world gems. There are ten kinds, and once a world\'s gems are taken they\'re gone.',
		'bullets' => [ 'A cutaway from crust to white-hot core', 'Probes melt, crush and overheat', 'Collect all ten to forge the Crown of Worlds' ],
		'shots' => [ [ 'orbit', 'Scanning a verdant core' ], [ 'orbit-giant', 'Diving into a gas giant' ] ],
	],
	[
		'id'    => 'sea',
		'name'  => 'Dive the deep',
		'kicker'=> 'The Deep Sea',
		'text'  => 'Oceans are deep enough to swim. Go under and the view turns to caustics and murk. Keep going and you drop into the Deep Sea, a 2D ocean slice from the Sunlit Zone to the Abyss, full of kelp, pearl clams, anglerfish and a leviathan.',
		'bullets' => [ 'Four ocean zones, darker and richer with depth', 'Scan fish schools, jellies, anglers and the leviathan', 'Build a Pressure Hull to survive the Abyss' ],
		'shots' => [ [ 'sea-3d', 'Under the surface' ], [ 'sea-twilight', 'The Twilight Zone' ], [ 'sea-midnight', 'Anglers in the Midnight Zone' ] ],
	],
	[
		'id'    => 'volcano',
		'name'  => 'Outrun the eruption',
		'kicker'=> 'Eruption Run',
		'text'  => 'Climb down a Volcanic Vent into a cutaway of the mountain: the Crater, Lava Tubes, Obsidian Galleries and Magma Chamber. Magma rises the whole time. Mine fire opals, ride geysers, and get out before it blows.',
		'bullets' => [ 'A two and a half minute race against the magma', 'Deeper pockets hold richer crystals', 'Heat, jet fuel, geysers and lava pools' ],
		'shots' => [ [ 'volcano-vent', 'A Volcanic Vent' ], [ 'volcano-crater', 'Climbing into the crater' ], [ 'volcano-chamber', 'The Magma Chamber' ] ],
	],
	[
		'id'    => 'warp',
		'name'  => 'Survive hyperspace',
		'kicker'=> 'Pirate interdictions',
		'text'  => 'Every jump between stars flies you down a tunnel of light. On dangerous lanes, pirates drop in mid-jump: swarm drones that dive at you, raiders and gunships, and mine fields. Aim, fire and dodge to the far end.',
		'bullets' => [ 'Mouse-aimed cannons and homing missiles', 'Relight the Circuit for safer jumps', 'Try the mini-game version below' ],
		'shots' => [ [ 'warp-fight', 'A firefight in the tunnel' ], [ 'warp-tunnel', 'A calm jump' ], [ 'warp-relay', 'Riding the relit Circuit' ] ],
	],
	[
		'id'    => 'home',
		'name'  => 'Keep a home',
		'kicker'=> 'The Homespace',
		'text'  => 'Robots are nomads, so home lives inside you. Press Y anywhere to step into a small digital room: a Vault for what your hold can\'t carry, an Inbox of trader orders, and a Dispatch Bay where copies of you work the worlds you\'ve visited.',
		'bullets' => [ 'Send subroutine workers to gather, survey and haul', 'Decor, themes, and Observatory and Garden wings', 'A Defrag Pod, a Trophy Wall and a lo-fi home theme' ],
		'shots' => [ [ 'home-room', 'The Dispatch Bay' ], [ 'home-dispatch', 'Planning a job' ], [ 'home-observatory', 'The Observatory wing' ] ],
	],
];

$tracks = [
	[ 'menu', 'Title Theme', 'Lydian pads under a drifting bell melody.' ],
	[ 'verdant', 'Verdant Worlds', 'Marimba and plucks for green planets.' ],
	[ 'arid', 'Arid Worlds', 'Dorian drones and dusty plucks.' ],
	[ 'crystal', 'Crystal Worlds', 'Glassy bells ringing out over ice and crystal.' ],
	[ 'ember', 'Volcanic Worlds', 'Phrygian menace for lava worlds and the Eruption Run.' ],
	[ 'town', 'Trade Hub', 'A cozy town theme with soft percussion.' ],
	[ 'space', 'Deep Space', 'Slow, wide pads between the planets.' ],
	[ 'orbit', 'Holding Orbit', 'A hovering pulse while probes drop into the core.' ],
	[ 'ocean', 'The Deep Sea', 'Sunlit water, far-off bells and whale song.' ],
	[ 'abyss', 'The Abyss', 'The same sea, past where the light gives out.' ],
	[ 'underground', 'The Deep', 'Caves, tunnels and sealed chambers.' ],
	[ 'hyperspace', 'Interdiction', 'Driving synthwave for pirate fights in hyperspace.' ],
	[ 'home', 'Homespace', 'A lo-fi loop for the room inside your robot.' ],
	[ 'combat', 'Combat Layer', 'The track that crossfades in when drones give chase.' ],
];
?><!doctype html>
<html <?php language_attributes(); ?>>
<head>
<meta charset="<?php bloginfo( 'charset' ); ?>">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Star Circuit: pick a robot, walk tiny planets, dive oceans, outrun eruptions and relight the galaxy. A free space-RPG built with Blender and Godot.">
<?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>

<nav class="nav" id="nav">
	<a class="brand" href="#top"><span class="brand-mark"></span>Star Circuit</a>
	<div class="nav-links">
		<a href="#robots">Robots</a>
		<a href="#modes">Explore</a>
		<a href="#galaxy">Galaxy</a>
		<a href="#music">Soundtrack</a>
		<a href="#play">Play</a>
		<a class="nav-cta" href="#download">Download</a>
	</div>
</nav>

<header class="hero" id="top">
	<canvas id="starfield" aria-hidden="true"></canvas>
	<div class="hero-inner">
		<p class="kicker">A robot space-RPG · v<?php echo esc_html( $version ); ?></p>
		<h1 class="title">STAR<br>CIRCUIT</h1>
		<p class="lede">The Circuit went dark long ago. Pick a robot, walk tiny planets, dive oceans, outrun eruptions, and relight the galaxy one relay at a time.</p>
		<div class="hero-actions">
			<a class="btn btn-primary" href="#download">Download for macOS</a>
			<button class="btn btn-ghost" id="warp-btn" type="button">Engage warp <span class="key">hold</span></button>
		</div>
	</div>
	<a class="scroll-hint" href="#robots" aria-label="Scroll down"></a>
</header>

<section class="stats" aria-label="By the numbers">
	<?php foreach ( [ [ 'stars', 'Star systems' ], [ 'worlds', 'Worlds and moons' ], [ 'quests', 'Story quests' ], [ 'recipes', 'Recipes' ], [ 'milestones', 'Milestones' ] ] as [ $k, $label ] ) : ?>
	<div class="stat"><span class="stat-n" data-count="<?php echo (int) ( $counts[ $k ] ?? 0 ); ?>">0</span><span class="stat-l"><?php echo esc_html( $label ); ?></span></div>
	<?php endforeach; ?>
</section>

<section class="section" id="robots">
	<div class="section-head">
		<p class="kicker">Choose your frame</p>
		<h2>Four robots, four ways to play</h2>
	</div>
	<div class="robots">
		<div class="robot-stage">
			<img id="robot-img" src="<?php echo esc_url( $img . 'robot-scout.jpg' ); ?>" alt="">
			<div class="robot-ring"></div>
		</div>
		<div class="robot-info">
			<h3 id="robot-name">Vesper</h3>
			<p class="robot-title" id="robot-title">Scout Unit</p>
			<p id="robot-desc"></p>
			<p class="ability"><span>Ability</span> <strong id="robot-ability"></strong> <em id="robot-ability-desc"></em></p>
			<ul class="perks" id="robot-perks"></ul>
			<div class="robot-tabs" id="robot-tabs" role="tablist"></div>
		</div>
	</div>
</section>

<section class="section" id="modes">
	<div class="section-head">
		<p class="kicker">Above, below and between</p>
		<h2>So many ways to explore</h2>
	</div>
	<div class="modes">
		<div class="mode-tabs" role="tablist">
			<?php foreach ( $modes as $i => $m ) : ?>
			<button class="mode-tab<?php echo 0 === $i ? ' active' : ''; ?>" data-mode="<?php echo esc_attr( $m['id'] ); ?>" role="tab" type="button">
				<span><?php echo esc_html( $m['kicker'] ); ?></span><?php echo esc_html( $m['name'] ); ?>
			</button>
			<?php endforeach; ?>
		</div>
		<?php foreach ( $modes as $i => $m ) : ?>
		<article class="mode<?php echo 0 === $i ? ' active' : ''; ?>" data-mode="<?php echo esc_attr( $m['id'] ); ?>">
			<div class="mode-media">
				<?php foreach ( $m['shots'] as $j => [ $file, $cap ] ) : ?>
				<figure class="shot<?php echo 0 === $j ? ' active' : ''; ?>">
					<img loading="lazy" src="<?php echo esc_url( $img . $file . '.jpg' ); ?>" alt="<?php echo esc_attr( $cap ); ?>" data-full="<?php echo esc_url( $img . $file . '.jpg' ); ?>">
					<figcaption><?php echo esc_html( $cap ); ?></figcaption>
				</figure>
				<?php endforeach; ?>
				<?php if ( count( $m['shots'] ) > 1 ) : ?>
				<div class="dots"><?php foreach ( $m['shots'] as $j => $unused ) : ?><button type="button" class="dot<?php echo 0 === $j ? ' active' : ''; ?>" aria-label="Screenshot <?php echo (int) $j + 1; ?>"></button><?php endforeach; ?></div>
				<?php endif; ?>
			</div>
			<div class="mode-copy">
				<p class="kicker"><?php echo esc_html( $m['kicker'] ); ?></p>
				<h3><?php echo esc_html( $m['name'] ); ?></h3>
				<p><?php echo esc_html( $m['text'] ); ?></p>
				<ul><?php foreach ( $m['bullets'] as $b ) : ?><li><?php echo esc_html( $b ); ?></li><?php endforeach; ?></ul>
			</div>
		</article>
		<?php endforeach; ?>
	</div>
</section>

<section class="section" id="galaxy">
	<div class="section-head">
		<p class="kicker">The real map</p>
		<h2>Explore the galaxy</h2>
		<p class="sub">This is the actual galaxy from the game: <?php echo (int) ( $counts['stars'] ?? 48 ); ?> stars, generated from a seed. Hover a star to see its worlds. Click two stars to plot a warp route and see how many jumps it takes.</p>
	</div>
	<div class="galaxy">
		<canvas id="galaxy-map"></canvas>
		<aside class="star-card" id="star-card">
			<p class="kicker">Star system</p>
			<h3>Hover a star</h3>
			<p class="muted">Solace, the home system, glows at the centre. The three edge worlds sit at the rim.</p>
		</aside>
		<div class="galaxy-legend" id="galaxy-legend"></div>
	</div>
</section>

<section class="section" id="music">
	<div class="section-head">
		<p class="kicker">Synthesised from code</p>
		<h2>The soundtrack</h2>
		<p class="sub">Every note is generated by a Python synth in the repo: no samples, no DAW. Pick a track.</p>
	</div>
	<div class="player">
		<div class="player-main">
			<canvas id="viz" aria-hidden="true"></canvas>
			<div class="now">
				<p class="kicker" id="now-kicker">Now playing</p>
				<h3 id="now-title">Title Theme</h3>
				<p class="muted" id="now-desc">Press play.</p>
			</div>
			<div class="controls">
				<button type="button" class="ctl" id="prev" aria-label="Previous">⏮</button>
				<button type="button" class="ctl ctl-play" id="play-btn" aria-label="Play">▶</button>
				<button type="button" class="ctl" id="next" aria-label="Next">⏭</button>
				<input type="range" id="seek" min="0" max="1000" value="0" aria-label="Seek">
				<span class="time" id="time">0:00</span>
				<input type="range" id="vol" min="0" max="100" value="70" aria-label="Volume">
			</div>
		</div>
		<ol class="tracks" id="tracks">
			<?php foreach ( $tracks as $i => [ $file, $name, $desc ] ) : ?>
			<li><button type="button" data-src="<?php echo esc_url( get_template_directory_uri() . '/assets/music/' . $file ); ?>" data-desc="<?php echo esc_attr( $desc ); ?>">
				<span class="n"><?php echo sprintf( '%02d', $i + 1 ); ?></span><span class="t"><?php echo esc_html( $name ); ?></span>
			</button></li>
			<?php endforeach; ?>
		</ol>
	</div>
</section>

<section class="section" id="play">
	<div class="section-head">
		<p class="kicker">Playable right here</p>
		<h2>Hyperspace run</h2>
		<p class="sub">Pirates have interdicted your jump. Steer with the mouse (or arrow keys / touch), click to fire, and survive to the end of the tunnel.</p>
	</div>
	<div class="game-wrap">
		<canvas id="hyper-game" width="960" height="540"></canvas>
		<div class="game-overlay" id="game-overlay">
			<h3>Interdiction!</h3>
			<p>Raiders fire from ahead, swarm drones dive at you, mines drift through.</p>
			<button class="btn btn-primary" id="game-start" type="button">Launch</button>
			<p class="muted" id="game-best"></p>
		</div>
	</div>
</section>

<section class="section download" id="download">
	<div class="section-head">
		<p class="kicker">Free and open source</p>
		<h2>Get Star Circuit</h2>
	</div>
	<div class="dl-grid">
		<div class="dl-card">
			<h3>macOS</h3>
			<p>Apple Silicon and Intel, macOS 11+. Download the zip from the latest release and unzip it. The first launch needs a right-click and Open, because the app isn't notarized.</p>
			<a class="btn btn-primary" href="<?php echo esc_url( $release ); ?>">Latest release</a>
		</div>
		<div class="dl-card">
			<h3>From source</h3>
			<p>Clone the repo, open <code>game/</code> in Godot 4.7, and press play. The models regenerate from a Blender script and the music from a Python synth.</p>
			<pre><code>git clone <?php echo esc_html( $repo ); ?>.git
godot --path star-circuit/game</code></pre>
			<a class="btn btn-ghost" href="<?php echo esc_url( $repo ); ?>">View on GitHub</a>
		</div>
	</div>
</section>

<footer class="footer">
	<p>Star Circuit · MIT licensed · Models built in Blender, engine Godot, soundtrack synthesised in Python.</p>
	<p class="muted">Made by Austin Ginder.</p>
</footer>

<div class="lightbox" id="lightbox" hidden><img alt=""><button type="button" aria-label="Close">✕</button></div>
<?php wp_footer(); ?>
</body>
</html>
