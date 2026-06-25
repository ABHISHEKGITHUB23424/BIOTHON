import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../data/india_locations.dart';

class LocationPickerField extends StatefulWidget {
  final String label;
  final IndiaLocation? selectedLocation;
  final ValueChanged<IndiaLocation?> onLocationSelected;
  final IconData prefixIcon;

  const LocationPickerField({
    Key? key,
    required this.label,
    required this.selectedLocation,
    required this.onLocationSelected,
    this.prefixIcon = Icons.domain_outlined,
  }) : super(key: key);

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  final FocusNode _focusNode = FocusNode();
  bool _isClickingDropdown = false;
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  OverlayEntry? _overlayEntry;
  List<IndiaLocation> _filteredLocations = [];
  Timer? _debounce;
  bool _isLoading = false;
  final Object _tapRegionGroupId = Object();

  @override
  void initState() {
    super.initState();
    _filteredLocations = indiaLocations;
    if (widget.selectedLocation != null) {
      _controller.text = widget.selectedLocation!.name;
    }
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(LocationPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedLocation != oldWidget.selectedLocation) {
      if (widget.selectedLocation != null) {
        _controller.text = widget.selectedLocation!.name;
      } else {
        _controller.clear();
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _hideOverlay();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    print('LocationPickerField: _onFocusChange. hasFocus: ${_focusNode.hasFocus}');
    if (_focusNode.hasFocus) {
      // Select all text on focus so typing immediately overwrites it
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
      _showOverlay();
    } else {
      // Revert text to selected location name if input was left incomplete
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        if (!_focusNode.hasFocus) {
          if (_isClickingDropdown) {
            // Keep overlay open so click event registers
            return;
          }
          _hideOverlay();
          if (widget.selectedLocation != null) {
            _controller.text = widget.selectedLocation!.name;
          } else {
            _controller.clear();
          }
          _filteredLocations = indiaLocations;
        }
      });
    }
  }

  void _showOverlay() {
    print('LocationPickerField: _showOverlay called.');
    _hideOverlay();
    if (!mounted) return;
    
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);
    
    // Check available vertical space below the field
    final double screenHeight = MediaQuery.of(context).size.height;
    final double spaceBelow = screenHeight - position.dy - size.height;
    const double overlayMaxHeight = 250.0;
    
    // Show above if space below is less than max height and there's more space above
    final bool showAbove = spaceBelow < overlayMaxHeight && position.dy > spaceBelow;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: showAbove ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: showAbove ? Alignment.bottomLeft : Alignment.topLeft,
          offset: showAbove ? const Offset(0, -5) : const Offset(0, 5),
          child: Listener(
            onPointerDown: (_) {
              print('LocationPickerField: onPointerDown inside dropdown.');
              _isClickingDropdown = true;
            },
            child: TapRegion(
              groupId: _tapRegionGroupId,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: overlayMaxHeight),
                    child: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B0000)),
                              ),
                            ),
                          )
                        : _filteredLocations.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'No locations found',
                                  style: TextStyle(color: Colors.black54, fontSize: 14),
                                ),
                              )
                            : Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: _scrollController,
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: _filteredLocations.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                  itemBuilder: (context, index) {
                                    final loc = _filteredLocations[index];
                                    return ListTile(
                                      leading: const Icon(Icons.place_outlined, color: Color(0xFF8B0000), size: 20),
                                      title: Text(
                                        loc.name,
                                        style: const TextStyle(
                                          color: Color(0xFF2C2C2C),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        loc.state,
                                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      hoverColor: const Color(0xFFF1F5F9),
                                      onTap: () {
                                        print('LocationPickerField: ListTile onTap fired for ${loc.name}');
                                        _isClickingDropdown = false;
                                        widget.onLocationSelected(loc);
                                        _controller.text = loc.name;
                                        _focusNode.unfocus();
                                        _hideOverlay();
                                      },
                                    );
                                  },
                                ),
                              ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    print('LocationPickerField: _hideOverlay called.');
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _filterLocations(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _filteredLocations = indiaLocations;
        _isLoading = false;
      });
      _overlayEntry?.markNeedsBuild();
      return;
    }

    setState(() {
      _isLoading = true;
    });
    _overlayEntry?.markNeedsBuild();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final encodedQuery = Uri.encodeComponent(query);
        const apiKey = '1d6b9e8325e840f48096e1063e04ffe6';
        final url = Uri.parse(
          'https://api.geoapify.com/v1/geocode/autocomplete?text=$encodedQuery&filter=countrycode:in&limit=10&apiKey=$apiKey'
        );
        final response = await http.get(url).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data != null && data['features'] != null) {
            final List<IndiaLocation> results = [];
            for (var feature in data['features']) {
              final props = feature['properties'];
              if (props != null) {
                final lat = double.tryParse(props['lat']?.toString() ?? '') ?? 0.0;
                final lon = double.tryParse(props['lon']?.toString() ?? '') ?? 0.0;
                
                final formatted = props['formatted'] as String? ?? '';
                final parts = formatted.split(',').map((s) => s.trim()).toList();
                String name = '';
                if (parts.length > 2) {
                  name = parts.sublist(0, parts.length - 2).join(', ');
                } else {
                  name = formatted;
                }
                
                if (name.isEmpty) {
                  name = props['city'] ?? props['name'] ?? props['county'] ?? 'Unknown';
                }
                
                final state = props['state'] as String? ?? '';
                
                results.add(IndiaLocation(
                  name: name,
                  state: state,
                  latitude: lat,
                  longitude: lon,
                ));
              }
            }

            if (mounted && _focusNode.hasFocus) {
              setState(() {
                _filteredLocations = results;
                _isLoading = false;
              });
              _overlayEntry?.markNeedsBuild();
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching autocomplete locations: $e');
      }

      // Offline fallback
      if (mounted && _focusNode.hasFocus) {
        setState(() {
          _filteredLocations = indiaLocations
              .where((loc) =>
                  loc.name.toLowerCase().contains(query.toLowerCase()) ||
                  loc.state.toLowerCase().contains(query.toLowerCase()))
              .toList();
          _isLoading = false;
        });
        _overlayEntry?.markNeedsBuild();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapRegionGroupId,
      onTapOutside: (event) {
        print('LocationPickerField: onTapOutside triggered.');
        _isClickingDropdown = false;
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
        }
        _hideOverlay();
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _filterLocations,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Search city or region...',
            prefixIcon: Icon(widget.prefixIcon, color: const Color(0xFF8B0000)),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _controller.clear();
                        _filterLocations('');
                        widget.onLocationSelected(null);
                      });
                      _focusNode.requestFocus();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(Icons.clear, color: Colors.grey, size: 18),
                    ),
                  ),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF8B0000)),
                const SizedBox(width: 12),
              ],
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF8B0000), width: 1.5),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            labelStyle: const TextStyle(color: Colors.black54),
          ),
          style: const TextStyle(color: Colors.black87),
        ),
      ),
    );
  }
}
