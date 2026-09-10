extends Resource
class_name CaveWorldStreamingConfig
## Inspector-editable, saveable-as-.tres configuration for CaveChunkStreamer.
## chunk_config's map_width/map_height IS the chunk size (e.g. 40x40, see
## presets/chunk_cave.tres) -- CaveChunkStreamer forwards it to CaveBuilder
## directly rather than relying on matching scene-file wiring, so the two
## can never drift out of sync.

@export_group("Chunking")
@export var chunk_config: CaveGenerationConfig
## World seed. 0 = randomize once at level start. chunk_config.seed is
## unused for chunked generation -- only chunk_coord + this seed matter (see
## CaveGenerator.generate_chunk()).
@export var seed: int = 0

@export_group("Streaming")
## Chebyshev-radius, in chunks, built synchronously at level load -- the
## player must never see an unloaded chunk in the first few steps in any
## direction. Keep small; this cost is paid up front, unbudgeted.
@export var initial_load_radius_chunks: int = 2
## Steady-state Chebyshev radius, in chunks, that stays loaded/visible.
@export var load_radius_chunks: int = 3
## Extra ring built proactively beyond load_radius_chunks, before the player
## is anywhere near its edge, so a chunk's load cost is paid off-screen.
@export var preload_margin_chunks: int = 1
## Hysteresis: chunks only unload once further than this from the player's
## current chunk (must be >= load_radius_chunks + preload_margin_chunks, or
## chunks would unload the instant they're queued) -- prevents load/unload
## thrashing right at the boundary.
@export var keep_radius_chunks: int = 4
## Delay clearing an out-of-range chunk. A short grace period lets boundary
## oscillation reuse the already-painted chunk instead of rebuilding it.
@export var unload_grace_seconds: float = 1.5
## Bounded generated-data LRU retained after a grace-period unload. Retained
## data is pure CaveData and is repainted on reuse; mutations remain in the
## streamer's save record rather than in this cache.
@export var retained_chunk_capacity: int = 4
## Never start a second chunk build while one is already running -- bounds
## the worst-case per-frame cost to exactly one chunk's, never compounding.
@export var max_chunk_loads_in_flight: int = 1
