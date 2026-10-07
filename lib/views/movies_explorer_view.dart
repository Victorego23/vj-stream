import 'dart:async';
import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'detail_view.dart';

/// Vista de Explorador Masivo de Películas (50,000+ Títulos) para TOM TV
/// Diseñado para Smart TV (D-Pad) y dispositivos móviles con paginación infinita y filtros avanzados.
class MoviesExplorerView extends StatefulWidget {
  final String? initialPlatform;
  final int? initialGenreId;
  final String? initialCollection;

  const MoviesExplorerView({
    super.key,
    this.initialPlatform,
    this.initialGenreId,
    this.initialCollection,
  });

  @override
  State<MoviesExplorerView> createState() => _MoviesExplorerViewState();
}

class _MoviesExplorerViewState extends State<MoviesExplorerView> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Estados de Filtros
  String _selectedPlatform = 'todas';
  int? _selectedGenreId;
  String _selectedYearRange = 'todos';
  String? _selectedCollection;
  String _currentQuery = '';
  Timer? _searchDebounce;

  // Estados de Paginación y Carga
  final List<MediaItem> _movies = [];
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;

  // Sagas y Plataformas
  List<Map<String, dynamic>> _collections = [];

  final List<Map<String, dynamic>> _platforms = [
    {'id': 'todas', 'name': 'Todas', 'icon': Icons.movie_filter_rounded, 'color': 0xFFE50914},
    {'id': 'netflix', 'name': 'Netflix', 'icon': Icons.play_circle_filled_rounded, 'color': 0xFFE50914},
    {'id': 'disney+', 'name': 'Disney+', 'icon': Icons.stars_rounded, 'color': 0xFF113CCF},
    {'id': 'max', 'name': 'Max (HBO)', 'icon': Icons.local_movies_rounded, 'color': 0xFF002BE7},
    {'id': 'prime video', 'name': 'Prime Video', 'icon': Icons.video_library_rounded, 'color': 0xFF00A8E1},
    {'id': 'apple tv+', 'name': 'Apple TV+', 'icon': Icons.apple_rounded, 'color': 0xFFFFFFFF},
    {'id': 'paramount+', 'name': 'Paramount+', 'icon': Icons.tv_rounded, 'color': 0xFF0064FF},
  ];

  final List<Map<String, dynamic>> _genres = [
    {'id': null, 'name': 'Todos los Géneros'},
    {'id': 28, 'name': 'Acción'},
    {'id': 878, 'name': 'Ciencia Ficción'},
    {'id': 27, 'name': 'Terror'},
    {'id': 35, 'name': 'Comedia'},
    {'id': 12, 'name': 'Aventura'},
    {'id': 16, 'name': 'Animación'},
    {'id': 53, 'name': 'Suspenso'},
    {'id': 18, 'name': 'Drama'},
    {'id': 10751, 'name': 'Familiar'},
    {'id': 14, 'name': 'Fantasía'},
  ];

  final List<Map<String, dynamic>> _yearRanges = [
    {'id': 'todos', 'name': 'Cualquier Año', 'min': null, 'max': null},
    {'id': '2026', 'name': 'Estrenos 2026', 'year': 2026},
    {'id': '2025', 'name': 'Cine 2025', 'year': 2025},
    {'id': '2024', 'name': 'Cine 2024', 'year': 2024},
    {'id': '2020-2023', 'name': '2020 - 2023', 'min': 2020, 'max': 2023},
    {'id': '2010s', 'name': 'Década 2010', 'min': 2010, 'max': 2019},
    {'id': '2000s', 'name': 'Años 2000', 'min': 2000, 'max': 2009},
    {'id': '90s', 'name': 'Clásicos 90s', 'min': 1990, 'max': 1999},
    {'id': '80s', 'name': 'Clásicos 80s', 'min': 1980, 'max': 1989},
  ];

  @override
  void initState() {
    super.initState();
    _selectedPlatform = widget.initialPlatform ?? 'todas';
    _selectedGenreId = widget.initialGenreId;
    _selectedCollection = widget.initialCollection;

    _scrollController.addListener(_onScroll);
    _loadCollections();
    _loadMovies(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 600 && !_isLoadingMore && _currentPage < _totalPages) {
      _loadNextPage();
    }
  }

  Future<void> _loadCollections() async {
    try {
      final list = await _apiService.fetchVodCollections();
      if (mounted && list.isNotEmpty) {
        setState(() => _collections = list);
      }
    } catch (_) {}
  }

  Future<void> _loadMovies({bool reset = false}) async {
    if (_isLoading) return;
    if (reset) {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _movies.clear();
      });
    }

    try {
      int? minYear;
      int? maxYear;
      int? specificYear;

      final range = _yearRanges.firstWhere((r) => r['id'] == _selectedYearRange, orElse: () => _yearRanges.first);
      if (range['year'] != null) {
        specificYear = range['year'];
      } else {
        minYear = range['min'];
        maxYear = range['max'];
      }

      final data = await _apiService.fetchVodMovies(
        page: _currentPage,
        limit: 30,
        genreId: _selectedGenreId,
        year: specificYear,
        minYear: minYear,
        maxYear: maxYear,
        platform: _selectedPlatform,
        collectionName: _selectedCollection,
        search: _currentQuery.isNotEmpty ? _currentQuery : null,
      );

      if (mounted) {
        setState(() {
          final List<MediaItem> results = data['results'] ?? [];
          _totalPages = data['totalPages'] ?? 1;
          if (reset) {
            _movies.clear();
            _movies.addAll(results);
          } else {
            _movies.addAll(results);
          }
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    await _loadMovies(reset: false);
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 380), () {
      setState(() {
        _currentQuery = query.trim();
      });
      _loadMovies(reset: true);
    });
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailView(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTv = screenWidth > 680 || (MediaQuery.of(context).orientation == Orientation.landscape && screenWidth > 520);
    final crossAxisCount = (screenWidth / (isTv ? 165 : 125)).floor().clamp(2, 8);

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Negro absoluto OLED
      body: SafeArea(
        child: Column(
          children: [
            // 1. Barra de Encabezado Superior (Búsqueda y Título)
            _buildHeader(isTv),

            // 2. Barra de Filtros por Plataforma de Streaming
            _buildPlatformsFilter(),

            // 3. Barra de Filtros por Género y Décadas
            _buildSubFilters(),

            // 4. Carrusel de Sagas y Colecciones (Si no hay búsqueda activa)
            if (_currentQuery.isEmpty && _collections.isNotEmpty && _selectedCollection == null)
              _buildCollectionsCarousel(isTv),

            // 5. Cuadrícula Infinita de Películas
            Expanded(
              child: _buildMoviesGrid(crossAxisCount, isTv),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTv) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0C14),
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'CINE & PELÍCULAS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '50K+ TÍTULOS',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const Text(
                'Español Latino (🇲🇽) y Calidad Full HD / 4K por Defecto',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          // Campo de búsqueda en tiempo real
          SizedBox(
            width: isTv ? 280 : 150,
            height: 38,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar películas...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF141824),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE50914), width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformsFilter() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF07080E),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _platforms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final p = _platforms[index];
          final isSelected = _selectedPlatform == p['id'];
          final color = Color(p['color'] as int);

          return InkWell(
            onTap: () {
              setState(() {
                _selectedPlatform = p['id'];
                _selectedCollection = null;
              });
              _loadMovies(reset: true);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.25) : const Color(0xFF101420),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? color : const Color(0x1FFFFFFF),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(p['icon'] as IconData, size: 14, color: isSelected ? Colors.white : Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    p['name'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF05060A),
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF), width: 1)),
      ),
      child: Row(
        children: [
          // Selector de Géneros
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _genres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final g = _genres[index];
                  final isSelected = _selectedGenreId == g['id'];
                  return ChoiceChip(
                    label: Text(g['name']),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        _selectedGenreId = val ? g['id'] : null;
                      });
                      _loadMovies(reset: true);
                    },
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: const Color(0xFF0E111A),
                    selectedColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    side: BorderSide(color: isSelected ? const Color(0xFFE50914) : const Color(0x1AFFFFFF)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Selector de Años / Décadas
          PopupMenuButton<String>(
            tooltip: 'Filtrar por Año / Década',
            initialValue: _selectedYearRange,
            color: const Color(0xFF141824),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF141824),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    _yearRanges.firstWhere((r) => r['id'] == _selectedYearRange)['name'],
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Colors.white70),
                ],
              ),
            ),
            onSelected: (val) {
              setState(() => _selectedYearRange = val);
              _loadMovies(reset: true);
            },
            itemBuilder: (context) {
              return _yearRanges.map((r) {
                return PopupMenuItem<String>(
                  value: r['id'],
                  child: Text(
                    r['name'],
                    style: TextStyle(
                      color: _selectedYearRange == r['id'] ? const Color(0xFFE50914) : Colors.white,
                      fontSize: 12,
                      fontWeight: _selectedYearRange == r['id'] ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionsCarousel(bool isTv) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF070910),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFFE50914), size: 14),
                const SizedBox(width: 6),
                const Text(
                  'Sagas & Universos Cinematográficos',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_selectedCollection != null)
                  InkWell(
                    onTap: () {
                      setState(() => _selectedCollection = null);
                      _loadMovies(reset: true);
                    },
                    child: const Text('Limpiar Saga ✕', style: TextStyle(color: Color(0xFFE50914), fontSize: 11)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: isTv ? 65 : 55,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _collections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final col = _collections[index];
                final isSelected = _selectedCollection == col['name'];

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCollection = isSelected ? null : col['name'];
                    });
                    _loadMovies(reset: true);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: isTv ? 190 : 150,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF281014) : const Color(0xFF10131E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFE50914) : const Color(0x1EFFFFFF),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        if ((col['posterUrl'] ?? '').toString().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              col['posterUrl'],
                              width: 30,
                              height: 42,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.movie_rounded, size: 24, color: Colors.white24),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                col['name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${col["count"] ?? 0} Películas',
                                style: const TextStyle(color: Colors.white38, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoviesGrid(int crossAxisCount, bool isTv) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFE50914)),
            SizedBox(height: 12),
            Text(
              'Cargando catálogo masivo en Español Latino...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_movies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_creation_outlined, size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              const Text(
                'No se encontraron películas para este filtro',
                style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Intenta seleccionar "Cualquier Año", otra plataforma o limpia el término de búsqueda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() {
                    _selectedPlatform = 'todas';
                    _selectedGenreId = null;
                    _selectedYearRange = 'todos';
                    _selectedCollection = null;
                    _searchController.clear();
                    _currentQuery = '';
                  });
                  _loadMovies(reset: true);
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Restablecer Filtros'),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.64,
              crossAxisSpacing: isTv ? 14 : 10,
              mainAxisSpacing: isTv ? 16 : 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final movie = _movies[index];
                return TvFocusableCard(
                  item: movie,
                  onTap: () => _openDetail(movie),
                );
              },
              childCount: _movies.length,
            ),
          ),
        ),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 2.5),
              ),
            ),
          ),
      ],
    );
  }
}
