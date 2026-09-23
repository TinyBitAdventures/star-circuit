<?php
/**
 * Star Circuit theme: a single interactive page. Game data (robots, galaxy,
 * counts) is exported from the Godot project into assets/data/game.json.
 */

defined( 'ABSPATH' ) || exit;

add_action( 'after_setup_theme', function () {
	add_theme_support( 'title-tag' );
	add_theme_support( 'html5', [ 'script', 'style' ] );
} );

/** Cache-bust each asset by its modified time. */
function star_circuit_asset( string $rel ): array {
	$path = get_template_directory() . '/' . $rel;
	return [ get_template_directory_uri() . '/' . $rel, file_exists( $path ) ? (string) filemtime( $path ) : '1' ];
}

add_action( 'wp_enqueue_scripts', function () {
	[ $css, $cv ] = star_circuit_asset( 'assets/css/site.css' );
	wp_enqueue_style( 'star-circuit', $css, [], $cv );
	[ $js, $jv ] = star_circuit_asset( 'assets/js/site.js' );
	wp_enqueue_script( 'star-circuit', $js, [], $jv, [ 'in_footer' => true, 'strategy' => 'defer' ] );
	[ $game, $gv ] = star_circuit_asset( 'assets/js/hyperspace-game.js' );
	wp_enqueue_script( 'star-circuit-game', $game, [], $gv, [ 'in_footer' => true, 'strategy' => 'defer' ] );
	wp_add_inline_script( 'star-circuit', 'window.STAR_CIRCUIT = ' . wp_json_encode( [
		'base' => get_template_directory_uri() . '/assets/',
		'data' => star_circuit_data(),
	] ) . ';', 'before' );
} );

/** The exported game data, decoded once per request. */
function star_circuit_data(): array {
	static $data = null;
	if ( null === $data ) {
		$file = get_template_directory() . '/assets/data/game.json';
		$data = file_exists( $file ) ? (array) json_decode( (string) file_get_contents( $file ), true ) : [];
	}
	return $data;
}

// A single page with no blog chrome: trim what WordPress adds to <head>.
remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
remove_action( 'wp_print_styles', 'print_emoji_styles' );
add_action( 'wp_enqueue_scripts', function () {
	wp_dequeue_style( 'wp-block-library' );
	wp_dequeue_style( 'global-styles' );
	wp_dequeue_style( 'classic-theme-styles' );
}, 100 );
add_filter( 'show_admin_bar', '__return_false' );
