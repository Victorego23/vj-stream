import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modelo de datos para un elemento del menú lateral de Smart TV
class TvSidebarItemData {
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback? onAction;

  const TvSidebarItemData({
    required this.id,
    required this.label,
    required this.icon,
    this.onAction,
  });
}

/// Menú lateral colapsable para Smart TV (Android TV / Google TV / Firestick).
/// Estilo nativo Netflix / YouTube TV con soporte 100% D-Pad.
class TvNavigationSidebar extends StatefulWidget {
  final String activeTabId;
  final ValueChanged<String> onSelectTab;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onRefresh;

  const TvNavigationSidebar({
    super.key,
    required this.activeTabId,
    required this.onSelectTab,
    required this.onSearch,
    required this.onSettings,
    required this.onRefresh,
  });

  @override
  State<TvNavigationSidebar> createState() => TvNavigationSidebarState();
}

class TvNavigationSidebarState extends State<TvNavigationSidebar> {
  bool _isExpanded = false;
  final Map<String, FocusNode> _focusNodes = {};

  void requestFocus([String? tabId]) {
    final targetId = tabId ?? widget.activeTabId;
    final node = _focusNodes[targetId] ?? _focusNodes['TV en Vivo'] ?? _focusNodes.values.firstOrNull;
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
    }
  }

  List<TvSidebarItemData> get _items => [
        TvSidebarItemData(
          id: 'search',
          label: 'Buscar',
          icon: Icons.search_rounded,
          onAction: widget.onSearch,
        ),
        TvSidebarItemData(
          id: 'Todos',
          label: 'Inicio',
          icon: Icons.home_rounded,
        ),
        TvSidebarItemData(
          id: 'Fútbol & Deportes',
          label: 'Fútbol & Deportes',
          icon: Icons.sports_soccer_rounded,
        ),
        TvSidebarItemData(
          id: 'Niños',
          label: 'Niños & Dibujos',
          icon: Icons.child_care_rounded,
        ),
        TvSidebarItemData(
          id: 'Telenovelas',
          label: 'Telenovelas',
          icon: Icons.favorite_rounded,
        ),
        TvSidebarItemData(
          id: 'TV en Vivo',
          label: 'TV en Vivo',
          icon: Icons.live_tv_rounded,
        ),
        TvSidebarItemData(
          id: 'Canales Perú',
          label: 'Canales Perú',
          icon: Icons.tv_rounded,
        ),
        TvSidebarItemData(
          id: 'Películas',
          label: 'Películas',
          icon: Icons.movie_rounded,
        ),
        TvSidebarItemData(
          id: 'Series',
          label: 'Series',
          icon: Icons.video_library_rounded,
        ),
        TvSidebarItemData(
          id: 'Mi Lista',
          label: 'Mi Lista',
          icon: Icons.star_rounded,
        ),
        TvSidebarItemData(
          id: 'refresh',
          label: 'Recargar',
          icon: Icons.refresh_rounded,
          onAction: widget.onRefresh,
        ),
        TvSidebarItemData(
          id: 'settings',
          label: 'Ajustes',
          icon: Icons.settings_rounded,
          onAction: widget.onSettings,
        ),
      ];

  @override
  void initState() {
    super.initState();
    for (final item in _items) {
      final node = FocusNode();
      node.addListener(() => _handleFocusChange(item.id, node));
      _focusNodes[item.id] = node;
    }
  }

  void _handleFocusChange(String id, FocusNode node) {
    if (!mounted) return;
    final anyHasFocus = _focusNodes.values.any((n) => n.hasFocus);
    if (_isExpanded != anyHasFocus) {
      setState(() {
        _isExpanded = anyHasFocus;
      });
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_isExpanded) setState(() => _isExpanded = true);
      },
      onExit: (_) {
        final anyHasFocus = _focusNodes.values.any((n) => n.hasFocus);
        if (!anyHasFocus && _isExpanded) {
          setState(() => _isExpanded = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: _isExpanded ? 240.0 : 72.0,
        decoration: BoxDecoration(
          color: const Color(0xFF0C0D13),
          border: const Border(
            right: BorderSide(color: Color(0xFF1E202C), width: 1.2),
          ),
          boxShadow: _isExpanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 28,
                    spreadRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            // Cabecera superior con logotipo de TOM TV
            _buildLogoHeader(),

            const Divider(color: Color(0xFF1E202C), height: 1, thickness: 1),

            // Lista de elementos navegables
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                children: [
                  for (final item in _items) _buildItemWidget(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoHeader() {
    return Container(
      height: 70,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: _isExpanded ? 16 : 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE50914), Color(0xFF990000)],
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66E50914),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Text(
              'TOM',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TV',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                    ),
                  ),
                  Text(
                    '4K SMART TV',
                    style: TextStyle(
                      color: Color(0xFFE50914),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemWidget(TvSidebarItemData item) {
    final focusNode = _focusNodes[item.id]!;
    final isSelected = widget.activeTabId == item.id;

    return _TvSidebarItem(
      item: item,
      focusNode: focusNode,
      isExpanded: _isExpanded,
      isSelected: isSelected,
      onTap: () {
        if (item.onAction != null) {
          item.onAction!();
        } else {
          widget.onSelectTab(item.id);
        }
      },
    );
  }
}

class _TvSidebarItem extends StatefulWidget {
  final TvSidebarItemData item;
  final FocusNode focusNode;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onTap;

  const _TvSidebarItem({
    required this.item,
    required this.focusNode,
    required this.isExpanded,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TvSidebarItem> createState() => _TvSidebarItemState();
}

class _TvSidebarItemState extends State<_TvSidebarItem> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_updateFocus);
  }

  @override
  void didUpdateWidget(covariant _TvSidebarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_updateFocus);
      widget.focusNode.addListener(_updateFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_updateFocus);
    super.dispose();
  }

  void _updateFocus() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color fgColor;
    Border? border;
    List<BoxShadow>? shadows;

    if (_isFocused) {
      bgColor = const Color(0xFFE50914);
      fgColor = Colors.white;
      border = Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5);
      shadows = [
        BoxShadow(
          color: const Color(0xFFE50914).withValues(alpha: 0.7),
          blurRadius: 14,
          spreadRadius: 2,
        ),
      ];
    } else if (widget.isSelected) {
      bgColor = const Color(0x26E50914);
      fgColor = const Color(0xFFE50914);
      border = Border.all(color: const Color(0x4DE50914), width: 1);
    } else {
      bgColor = Colors.transparent;
      fgColor = Colors.white70;
    }

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            if (widget.item.onAction == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (node.context != null) {
                  final moved = node.focusInDirection(TraversalDirection.right);
                  if (!moved) {
                    node.nextFocus();
                  }
                }
              });
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            // Salir del menú lateral hacia el contenido principal
            final moved = node.focusInDirection(TraversalDirection.right);
            if (!moved) {
              node.nextFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final moved = node.focusInDirection(TraversalDirection.down);
            if (moved) return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final moved = node.focusInDirection(TraversalDirection.up);
            if (moved) return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          widget.focusNode.requestFocus();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isExpanded ? 12 : 8,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: border,
            boxShadow: shadows,
          ),
          child: Row(
            mainAxisAlignment:
                widget.isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(
                widget.item.icon,
                color: fgColor,
                size: 20,
              ),
              if (widget.isExpanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 13,
                      fontWeight: _isFocused || widget.isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (widget.isSelected && !_isFocused)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE50914),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
