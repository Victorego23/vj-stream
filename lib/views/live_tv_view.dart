import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/live_channel.dart';
import '../services/api_service.dart';
import 'video_player_view.dart';

class LiveTvView extends StatefulWidget {
  const LiveTvView({super.key});

  @override
  State<LiveTvView> createState() => _LiveTvViewState();
}

class _LiveTvViewState extends State<LiveTvView> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  static const String _favsKey = 'vj_stream_fav_channel_ids';
  Set<String> _favoriteChannelIds = {};

  List<LiveChannel> _allChannels = [];
  List<String> _categories = ['Favoritos', 'Todos'];
  String _selectedCategory = 'Todos';
  String _selectedCountry = 'ALL';
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  static const List<Map<String, String>> _countryFilters = [
    {'code': 'ALL', 'label': '🌎 Todos'},
    {'code': 'pe', 'label': '🇵🇪 Perú'},
    {'code': 'mx', 'label': '🇲🇽 México'},
    {'code': 'ar', 'label': '🇦🇷 Argentina'},
    {'code': 'co', 'label': '🇨🇴 Colombia'},
    {'code': 'cl', 'label': '🇨🇱 Chile'},
    {'code': 'es', 'label': '🇪🇸 España'},
    {'code': 'us', 'label': '🇺🇸 USA'},
    {'code': 'do', 'label': '🇩🇴 Dominicana'},
    {'code': 'ec', 'label': '🇪🇨 Ecuador'},
    {'code': 've', 'label': '🇻🇪 Venezuela'},
    {'code': 'bo', 'label': '🇧🇴 Bolivia'},
    {'code': 'cr', 'label': '🇨🇷 Costa Rica'},
    {'code': 'py', 'label': '🇵🇾 Paraguay'},
    {'code': 'gt', 'label': '🇬🇹 Guatemala'},
    {'code': 'hn', 'label': '🇭🇳 Honduras'},
    {'code': 'sv', 'label': '🇸🇻 El Salvador'},
    {'code': 'pr', 'label': '🇵🇷 Puerto Rico'},
    {'code': 'pa', 'label': '🇵🇦 Panamá'},
    {'code': 'uy', 'label': '🇺🇾 Uruguay'},
  ];

  static String getChannelCountry(LiveChannel channel) {
    final match = RegExp(r'_([a-z]{2})$', caseSensitive: false).firstMatch(channel.id);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return 'other';
  }

  static String getCountryFlag(String code) {
    switch (code.toLowerCase()) {
      case 'pe': return '🇵🇪';
      case 'mx': return '🇲🇽';
      case 'ar': return '🇦🇷';
      case 'co': return '🇨🇴';
      case 'cl': return '🇨🇱';
      case 'es': return '🇪🇸';
      case 'us': return '🇺🇸';
      case 'do': return '🇩🇴';
      case 'ec': return '🇪🇨';
      case 've': return '🇻🇪';
      case 'bo': return '🇧🇴';
      case 'cr': return '🇨🇷';
      case 'py': return '🇵🇾';
      case 'gt': return '🇬🇹';
      case 'hn': return '🇭🇳';
      case 'sv': return '🇸🇻';
      case 'pr': return '🇵🇷';
      case 'pa': return '🇵🇦';
      case 'uy': return '🇺🇾';
      default: return '🌐';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadChannels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_favsKey) ?? [];
      if (mounted) {
        setState(() {
          _favoriteChannelIds = list.toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite(LiveChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        if (_favoriteChannelIds.contains(channel.id)) {
          _favoriteChannelIds.remove(channel.id);
        } else {
          _favoriteChannelIds.add(channel.id);
        }
      });
      await prefs.setStringList(_favsKey, _favoriteChannelIds.toList());
    } catch (_) {}
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiService.fetchLiveChannels();
      final channels = res['channels'] as List<LiveChannel>? ?? [];
      final categories = res['categories'] as List<String>? ?? [];

      if (mounted) {
        setState(() {
          _allChannels = channels;
          final cleanCats = categories.where((c) => c != 'Todos' && c != 'Favoritos').toList();
          _categories = ['Favoritos', 'Todos', ...cleanCats];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudieron cargar los canales de TV en vivo.';
          _isLoading = false;
        });
      }
    }
  }

  List<LiveChannel> get _filteredChannels {
    return _allChannels.where((channel) {
      final matchesCategory = _selectedCategory == 'Todos' ||
          (_selectedCategory == 'Favoritos'
              ? _favoriteChannelIds.contains(channel.id)
              : channel.category.toLowerCase() == _selectedCategory.toLowerCase());

      final channelCountry = getChannelCountry(channel);
      final matchesCountry = _selectedCountry == 'ALL' || channelCountry == _selectedCountry;

      final matchesSearch = _searchQuery.isEmpty ||
          channel.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          channel.category.toLowerCase().contains(_searchQuery.toLowerCase());

      return matchesCategory && matchesCountry && matchesSearch;
    }).toList();
  }

  String _getCategoryIcon(String cat) {
    if (cat == 'Favoritos') return '⭐ ';
    final lower = cat.toLowerCase();
    if (lower.contains('depor')) return '⚽ ';
    if (lower.contains('cine') || lower.contains('series')) return '🎬 ';
    if (lower.contains('infant') || lower.contains('kids')) return '👶 ';
    if (lower.contains('entreten') || lower.contains('cult')) return '🌍 ';
    if (lower.contains('nacion') || lower.contains('noti')) return '🌎 ';
    return '📺 ';
  }

  void _playChannel(LiveChannel channel) {
    final currentList = _filteredChannels;
    final initialIndex = currentList.indexWhere((c) => c.id == channel.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerView(
          videoUrl: channel.streamUrl,
          title: channel.name,
          qualityLabel: channel.quality,
          liveSources: channel.sources,
          isLive: true,
          liveChannel: channel,
          liveChannelsList: currentList,
          initialChannelIndex: initialIndex >= 0 ? initialIndex : 0,
        ),
      ),
    ).then((_) {
      _loadFavorites();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: RefreshIndicator(
        color: const Color(0xFFE50914),
        backgroundColor: const Color(0xFF16171F),
        onRefresh: _loadChannels,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Barra superior fija con Buscador
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE50914), Color(0xFF990000)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66E50914),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TV en Vivo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '${_allChannels.length} canales transmitiendo 24/7 con zapping',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Buscador de canales
                    TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF16171F),
                        hintText: 'Buscar canal (ej: ESPN, HBO, Cartoon, La 1)...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF232532)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF232532)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE50914), width: 1.5),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val.trim());
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Chips horizontales de categorías
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = cat.toLowerCase() == _selectedCategory.toLowerCase();
                    final icon = cat == 'Todos' ? '🌐 ' : _getCategoryIcon(cat);
                    final badgeCount = cat == 'Favoritos' && _favoriteChannelIds.isNotEmpty
                        ? ' (${_favoriteChannelIds.length})'
                        : '';

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedCategory = cat);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [Color(0xFFE50914), Color(0xFF990000)],
                                )
                              : null,
                          color: isSelected ? null : const Color(0xFF16171F),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFE50914) : const Color(0xFF232532),
                            width: 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFE50914).withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$icon$cat$badgeCount',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Chips horizontales de Países / Regiones
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 34,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _countryFilters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final c = _countryFilters[index];
                      final code = c['code']!;
                      final label = c['label']!;
                      final isSelected = _selectedCountry == code;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCountry = code);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFE50914).withValues(alpha: 0.22)
                                : const Color(0xFF13141C),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFE50914) : const Color(0xFF222432),
                              width: isSelected ? 1.2 : 0.8,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white60,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 14)),

            // Lista o Grid de Canales
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                ),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, color: Color(0xFFE50914), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _loadChannels,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_filteredChannels.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedCategory == 'Favoritos'
                            ? Icons.star_border_rounded
                            : Icons.tv_off_rounded,
                        color: _selectedCategory == 'Favoritos'
                            ? Colors.amber.withValues(alpha: 0.6)
                            : Colors.white38,
                        size: 52,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selectedCategory == 'Favoritos'
                            ? 'Aún no tienes canales favoritos\nToca la estrella (★) en cualquier canal para tenerlo a mano'
                            : 'No se encontraron canales en esta categoría',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                      ),
                      if (_searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _selectedCategory = 'Todos';
                            });
                          },
                          child: const Text('Limpiar búsqueda', style: TextStyle(color: Color(0xFFE50914))),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final channel = _filteredChannels[index];
                      return _buildChannelCard(channel);
                    },
                    childCount: _filteredChannels.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelCard(LiveChannel channel) {
    final isFav = _favoriteChannelIds.contains(channel.id);

    return InkWell(
      onTap: () => _playChannel(channel),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16171F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFav ? Colors.amber.withValues(alpha: 0.3) : const Color(0xFF232532),
            width: isFav ? 1.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isFav ? Colors.amber.withValues(alpha: 0.08) : Colors.black45,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera: Badge EN VIVO + Fuentes + Estrella Favorito
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66E50914),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_manual_record, color: Colors.white, size: 7),
                      const SizedBox(width: 3),
                      const Text(
                        'VIVO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        getCountryFlag(getChannelCountry(channel)),
                        style: const TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (channel.sources.length > 1) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF00E676).withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '${channel.sources.length}x',
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    GestureDetector(
                      onTap: () => _toggleFavorite(channel),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isFav
                              ? Colors.amber.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isFav
                                ? Colors.amber.withValues(alpha: 0.6)
                                : Colors.transparent,
                            width: 0.8,
                          ),
                        ),
                        child: Icon(
                          isFav ? Icons.star_rounded : Icons.star_border_rounded,
                          color: isFav ? Colors.amber : Colors.white54,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Logo central
            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0E14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: channel.logoUrl.isNotEmpty
                      ? Image.network(
                          channel.logoUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.tv_rounded, color: Colors.white38, size: 36),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.tv_rounded, color: Colors.white38, size: 36),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Nombre y categoría
            Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    channel.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  channel.quality,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
