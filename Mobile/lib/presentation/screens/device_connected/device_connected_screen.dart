import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/effect.dart';
import '../../../data/effects_data.dart';
import '../../../data/services/led_control_service.dart';
import '../../../l10n/app_localizations.dart';

// ============================================================================
// Locale helpers for Effect and Category names
// ============================================================================

/// Returns localized name for EffectCategory based on current locale
String getCategoryLocalizedName(EffectCategory category, BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'pl' ? category.nameLocal : category.name;
}

/// Returns localized name for Effect based on current locale
String getEffectLocalizedName(Effect effect, BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'pl' ? effect.nameLocal : effect.name;
}

/// Returns localized name for EffectParameter based on current locale
String getParamLocalizedName(EffectParameter param, BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'pl' ? param.nameLocal : param.name;
}

// ============================================================================
// LED Control Screen - Main control center for PixelTree
// ============================================================================

class DeviceConnectedScreen extends StatefulWidget {
  final String connectionType; // "BLE" or "AP"
  final String? deviceIp; // IP address for WiFi mode

  const DeviceConnectedScreen({
    super.key,
    required this.connectionType,
    this.deviceIp,
  });

  @override
  State<DeviceConnectedScreen> createState() => _DeviceConnectedScreenState();
}

class _DeviceConnectedScreenState extends State<DeviceConnectedScreen>
    with SingleTickerProviderStateMixin {
  late final LEDControlService _ledService;
  late final TabController _tabController;

  bool _isConnected = false;
  bool _isLoading = true;
  bool _powerOn = true;
  int _brightness = 180;
  int _selectedEffectId = 0;
  EffectCategory _selectedCategory = EffectCategory.static_;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: EffectCategory.values.length,
      vsync: this,
    );
    _tabController.addListener(_onCategoryChanged);

    // Initialize LED service with correct base URL
    final baseUrl = widget.deviceIp != null
        ? 'http://${widget.deviceIp}'
        : 'http://192.168.4.1';
    _ledService = LEDControlService(baseUrl: baseUrl);

    _initConnection();
  }

  void _onCategoryChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        _selectedCategory = EffectCategory.values[_tabController.index];
      });
    }
  }

  Future<void> _initConnection() async {
    try {
      final connected = await _ledService.isConnected();
      if (connected) {
        final status = await _ledService.getStatus();
        setState(() {
          _isConnected = true;
          _isLoading = false;
          _powerOn = status.power;
          _brightness = status.brightness;
          _selectedEffectId = status.effectId;
          // Set category based on selected effect
          final effect = getEffectById(status.effectId);
          if (effect != null) {
            _selectedCategory = effect.category;
            _tabController.index = EffectCategory.values.indexOf(
              _selectedCategory,
            );
          }
        });
      } else {
        setState(() {
          _isLoading = false;
          _isConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isConnected = false;
      });
    }
  }

  void _handleDisconnection() {
    if (mounted) {
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _onPowerToggle(bool value) async {
    setState(() => _powerOn = value);
    try {
      await _ledService.setPower(value);
    } catch (e) {
      _handleDisconnection();
    }
  }

  void _onBrightnessChanged(double value) {
    setState(() => _brightness = value.round());
    try {
      _ledService.setBrightnessThrottled(_brightness);
    } catch (e) {
      _handleDisconnection();
    }
  }

  void _onBrightnessChangeEnd(double value) {
    try {
      _ledService.setBrightnessFinal(value.round());
    } catch (e) {
      _handleDisconnection();
    }
  }

  void _onEffectSelected(Effect effect) async {
    setState(() => _selectedEffectId = effect.id);
    try {
      await _ledService.setEffect(effect.id);
      _showParameterSheet(effect);
    } catch (e) {
      _handleDisconnection();
    }
  }

  void _showParameterSheet(Effect effect) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ParameterSheet(
        effect: effect,
        ledService: _ledService,
        onDisconnection: _handleDisconnection,
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ledService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    if (!_isConnected) {
      return _buildConnectionError();
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Header with power and brightness
            _buildHeader(),
            // Category tabs
            _buildCategoryTabs(),
            // Effect grid
            Expanded(child: _buildEffectGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionError() {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 80, color: AppColors.error),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)?.ledControlNoConnection ??
                  'No Connection',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _initConnection();
              },
              icon: const Icon(Icons.refresh),
              label: Text(
                AppLocalizations.of(context)?.ledControlTryAgain ?? 'Try Again',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.forestGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top row: Title and Power
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.park,
                    color: _powerOn ? AppColors.forestGreen : Colors.grey,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.appName ?? 'PixelTree',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'APP',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Power switch
              _GlowSwitch(
                value: _powerOn,
                onChanged: _onPowerToggle,
                activeColor: AppColors.forestGreen,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Brightness slider
          Row(
            children: [
              Icon(
                Icons.brightness_low,
                color: Colors.white.withValues(alpha: 0.6),
                size: 20,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.gold,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                    thumbColor: AppColors.gold,
                    overlayColor: AppColors.gold.withValues(alpha: 0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _brightness.toDouble(),
                    min: 0,
                    max: 255,
                    onChanged: _powerOn ? _onBrightnessChanged : null,
                    onChangeEnd: _powerOn ? _onBrightnessChangeEnd : null,
                  ),
                ),
              ),
              Icon(
                Icons.brightness_high,
                color: Colors.white.withValues(alpha: 0.6),
                size: 20,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${(_brightness * 100 / 255).round()}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      color: AppColors.darkSurface,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.zero,
        indicatorColor: AppColors.gold,
        labelColor: AppColors.gold,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
        indicatorWeight: 3,
        tabs: EffectCategory.values.map((category) {
          return Tab(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(getCategoryLocalizedName(category, context)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEffectGrid() {
    final effects = getEffectsByCategory(_selectedCategory);

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: effects.length,
      itemBuilder: (context, index) {
        final effect = effects[index];
        final isSelected = effect.id == _selectedEffectId;

        return _EffectCard(
          effect: effect,
          isSelected: isSelected,
          onTap: () => _onEffectSelected(effect),
        );
      },
    );
  }
}

// ============================================================================
// Effect Card Widget
// ============================================================================

class _EffectCard extends StatelessWidget {
  final Effect effect;
  final bool isSelected;
  final VoidCallback onTap;

  const _EffectCard({
    required this.effect,
    required this.isSelected,
    required this.onTap,
  });

  IconData _getIconData(String iconName) {
    // Map icon names to Material icons
    final iconMap = {
      'circle': Icons.circle,
      'gradient': Icons.gradient,
      'blur_on': Icons.blur_on,
      'view_module': Icons.view_module,
      'waves': Icons.waves,
      'water': Icons.water,
      'sync_alt': Icons.sync_alt,
      'graphic_eq': Icons.graphic_eq,
      'theaters': Icons.theaters,
      'radar': Icons.radar,
      'star': Icons.star,
      'directions_run': Icons.directions_run,
      'android': Icons.android,
      'auto_awesome': Icons.auto_awesome,
      'flare': Icons.flare,
      'flash_on': Icons.flash_on,
      'diamond': Icons.diamond,
      'nights_stay': Icons.nights_stay,
      'local_fire_department': Icons.local_fire_department,
      'emoji_objects': Icons.emoji_objects,
      'whatshot': Icons.whatshot,
      'terrain': Icons.terrain,
      'landscape': Icons.landscape,
      'water_drop': Icons.water_drop,
      'pool': Icons.pool,
      'lightbulb': Icons.lightbulb,
      'park': Icons.park,
      'visibility': Icons.visibility,
      'celebration': Icons.celebration,
      'ac_unit': Icons.ac_unit,
      'sports_basketball': Icons.sports_basketball,
      'grain': Icons.grain,
      'blur_circular': Icons.blur_circular,
      'bolt': Icons.bolt,
      'code': Icons.code,
      'favorite': Icons.favorite,
      'self_improvement': Icons.self_improvement,
      'local_police': Icons.local_police,
      'flash_auto': Icons.flash_auto,
    };
    return iconMap[iconName] ?? Icons.auto_awesome;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.forestGreen.withValues(alpha: 0.3)
              : AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.forestGreen : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.forestGreen.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getIconData(effect.icon),
                size: 36,
                color: isSelected ? AppColors.gold : Colors.white70,
              ),
              const SizedBox(height: 8),
              Text(
                getEffectLocalizedName(effect, context),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Parameter Sheet
// ============================================================================

class _ParameterSheet extends StatefulWidget {
  final Effect effect;
  final LEDControlService ledService;
  final VoidCallback onDisconnection;

  const _ParameterSheet({
    required this.effect,
    required this.ledService,
    required this.onDisconnection,
  });

  @override
  State<_ParameterSheet> createState() => _ParameterSheetState();
}

class _ParameterSheetState extends State<_ParameterSheet> {
  final Map<String, dynamic> _paramValues = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentParams();
  }

  Future<void> _loadCurrentParams() async {
    // First set defaults as fallback
    for (final param in widget.effect.parameters) {
      _paramValues[param.id] = param.defaultValue;
    }

    // Then try to fetch current values from ESP32
    try {
      final currentParams = await widget.ledService.getParams();
      final paramsData = currentParams['params'] as Map<String, dynamic>?;

      if (paramsData != null && mounted) {
        setState(() {
          for (final param in widget.effect.parameters) {
            if (paramsData.containsKey(param.id)) {
              _paramValues[param.id] = paramsData[param.id];
            }
          }
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      // Connection error - close sheet and notify parent
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDisconnection();
      }
    }
  }

  void _onParamChanged(String key, dynamic value) {
    setState(() => _paramValues[key] = value);
    try {
      widget.ledService.setParamDebounced(key, value);
    } catch (e) {
      Navigator.of(context).pop();
      widget.onDisconnection();
    }
  }

  /// Get visible parameters based on current state
  /// Hides colorMiddle when threePoint is false
  /// Hides color3/4 when numColors < 3/4
  List<EffectParameter> _getVisibleParams() {
    final threePoint = _paramValues['threePoint'] as bool? ?? true;
    final numColors = (_paramValues['numColors'] as num?)?.toInt() ?? 4;

    return widget.effect.parameters.where((param) {
      // Hide colorMiddle when threePoint is off (Gradient effect)
      if (param.id == 'colorMiddle' && !threePoint) {
        return false;
      }

      // Hide color3 when numColors < 3 (Color Wave effect)
      if (param.id == 'color3' && numColors < 3) {
        return false;
      }

      // Hide color4 when numColors < 4 (Color Wave effect)
      if (param.id == 'color4' && numColors < 4) {
        return false;
      }

      // Hide color5 when numColors < 5
      if (param.id == 'color5' && numColors < 5) {
        return false;
      }

      // Hide color6 when numColors < 6
      if (param.id == 'color6' && numColors < 6) {
        return false;
      }

      // Hide color7 when numColors < 7
      if (param.id == 'color7' && numColors < 7) {
        return false;
      }

      // Hide color8 when numColors < 8
      if (param.id == 'color8' && numColors < 8) {
        return false;
      }

      // Hide color when rainbowMode is on (Theater Chase effect)
      final rainbowMode = _paramValues['rainbowMode'] as bool? ?? false;
      if (param.id == 'color' && rainbowMode) {
        return false;
      }

      // Hide Scanner colors based on numDots (effect 9 only)
      if (widget.effect.id == 9) {
        final numDots = _paramValues['numDots'] as int? ?? 1;
        if (param.id == 'color2' && numDots < 2) return false;
        if (param.id == 'color3' && numDots < 3) return false;
        if (param.id == 'color4' && numDots < 4) return false;
        if (param.id == 'color5' && numDots < 5) return false;
        if (param.id == 'color6' && numDots < 6) return false;
        if (param.id == 'color7' && numDots < 7) return false;
        if (param.id == 'color8' && numDots < 8) return false;
      }

      // Hide Running Lights colors based on numColors (effect 11)
      if (widget.effect.id == 11) {
        if (param.id == 'color2' && numColors < 2) return false;
        if (param.id == 'color3' && numColors < 3) return false;
        if (param.id == 'color4' && numColors < 4) return false;
      }

      // Hide Fade effect colors based on numColors (effect 39)
      if (widget.effect.id == 39) {
        if (param.id == 'color3' && numColors < 3) return false;
        if (param.id == 'color4' && numColors < 4) return false;
        if (param.id == 'color5' && numColors < 5) return false;
        if (param.id == 'color6' && numColors < 6) return false;
        if (param.id == 'color7' && numColors < 7) return false;
        if (param.id == 'color8' && numColors < 8) return false;
      }

      // Hide sparkleColor when sparkleEnabled is off (Comet effect)
      final sparkleEnabled = _paramValues['sparkleEnabled'] as bool? ?? true;
      if (param.id == 'sparkleColor' && !sparkleEnabled) {
        return false;
      }

      // Twinkle effect colorMode-based hiding (effect 13)
      if (widget.effect.id == 13) {
        final colorMode = _paramValues['colorMode'] as int? ?? 1;
        // Hide palette when colorMode != 1 (Paleta)
        if (param.id == 'palette' && colorMode != 1) return false;
        // Hide twinkleColor when colorMode != 0 (Jednokolorowy)
        if (param.id == 'twinkleColor' && colorMode != 0) return false;
      }

      // Sparkle effect darkMode-based hiding (effect 15)
      if (widget.effect.id == 15) {
        final darkMode = _paramValues['darkMode'] as bool? ?? false;
        // Hide colorSpark when darkMode is enabled (sparks are black)
        if (param.id == 'colorSpark' && darkMode) return false;
      }

      // Glitter effect rainbowBg-based hiding (effect 16)
      if (widget.effect.id == 16) {
        final rainbowBg = _paramValues['rainbowBg'] as bool? ?? true;
        // Hide colorBg when rainbowBg is enabled
        if (param.id == 'colorBg' && rainbowBg) return false;
      }

      // Fairy effect colorMode-based hiding (effect 25)
      if (widget.effect.id == 25) {
        final colorMode = (_paramValues['colorMode'] as num?)?.toInt() ?? 0;
        // Hide palette when colorMode != 3 (Paleta)
        if (param.id == 'palette' && colorMode != 3) return false;
      }

      // Generic dependsOn handling - hide when dependency param is false
      if (param.dependsOn != null) {
        final dependencyValue = _paramValues[param.dependsOn] as bool? ?? true;
        if (!dependencyValue) return false;
      }

      // Dissolve effect (38) - hide color when randomColors is true
      if (widget.effect.id == 38 && param.id == 'color') {
        final randomColors = _paramValues['randomColors'] as bool? ?? true;
        if (randomColors) return false;
      }

      // Strobe effect (41) - hide color only in Rainbow mode (2)
      if (widget.effect.id == 41 && param.id == 'color') {
        final mode = (_paramValues['mode'] as num?)?.toInt() ?? 0;
        if (mode == 2) return false; // Hide only in Rainbow
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.effect.nameLocal,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.forestGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    getCategoryLocalizedName(widget.effect.category, context),
                    style: const TextStyle(
                      color: AppColors.forestGreen,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Parameters list
          Flexible(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: AppColors.gold),
                    ),
                  )
                : ListView.builder(
                    key: ValueKey(
                      'params_${(_paramValues['numColors'] as num?)?.toInt() ?? 3}',
                    ),
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    itemCount: _getVisibleParams().length,
                    itemBuilder: (context, index) {
                      final param = _getVisibleParams()[index];
                      return KeyedSubtree(
                        key: ValueKey(param.id),
                        child: _buildParameterControl(param),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterControl(EffectParameter param) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            getParamLocalizedName(param, context),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          _buildControlWidget(param),
        ],
      ),
    );
  }

  Widget _buildControlWidget(EffectParameter param) {
    switch (param.type) {
      case ParameterType.uint8:
        final value =
            (_paramValues[param.id] as num?)?.toInt() ??
            (param.defaultValue as num).toInt();

        // Fairy colorMode (effect 25) - use buttons
        if (widget.effect.id == 25 && param.id == 'colorMode') {
          final l10n = AppLocalizations.of(context);
          final colorModeLabels = [
            l10n?.colorModeWarm ?? 'Warm',
            l10n?.colorModeCold ?? 'Cold',
            l10n?.colorModeMulti ?? 'Multi',
            l10n?.colorModePalette ?? 'Palette',
          ];
          return SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: colorModeLabels.length,
              itemBuilder: (context, index) {
                final isSelected = value == index;
                return GestureDetector(
                  onTap: () => _onParamChanged(param.id, index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.gold : AppColors.darkCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.gold : Colors.white24,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      colorModeLabels[index],
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }

        // ChristmasChase pattern (effect 26) - use buttons
        if (widget.effect.id == 26 && param.id == 'pattern') {
          final patternLabels = ['Alternating', 'Chase', 'Sparkle'];
          return SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: patternLabels.length,
              itemBuilder: (context, index) {
                final isSelected = value == index;
                return GestureDetector(
                  onTap: () => _onParamChanged(param.id, index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.gold : AppColors.darkCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.gold : Colors.white24,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      patternLabels[index],
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }

        // Police Lights style (effect 40) - use buttons
        if (widget.effect.id == 40 && param.id == 'style') {
          final styleLabels = ['Single', 'Solid', 'Alternating'];
          return SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: styleLabels.length,
              itemBuilder: (context, index) {
                final isSelected = value == index;
                return GestureDetector(
                  onTap: () => _onParamChanged(param.id, index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.gold : AppColors.darkCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.gold : Colors.white24,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      styleLabels[index],
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }

        // Strobe mode (effect 41) - use buttons
        if (widget.effect.id == 41 && param.id == 'mode') {
          final modeLabels = ['Normal', 'Mega', 'Rainbow'];
          return SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: modeLabels.length,
              itemBuilder: (context, index) {
                final isSelected = value == index;
                return GestureDetector(
                  onTap: () => _onParamChanged(param.id, index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.gold : AppColors.darkCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.gold : Colors.white24,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      modeLabels[index],
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }

        // Use +/- buttons if useIncrement is true
        if (param.useIncrement) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Minus button
              IconButton(
                onPressed: value > (param.min ?? 0)
                    ? () => _onParamChanged(param.id, value - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: value > (param.min ?? 0) ? AppColors.gold : Colors.grey,
                iconSize: 32,
              ),
              // Value display
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  value.toString(),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Plus button
              IconButton(
                onPressed: value < (param.max ?? 255)
                    ? () => _onParamChanged(param.id, value + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                color: value < (param.max ?? 255)
                    ? AppColors.gold
                    : Colors.grey,
                iconSize: 32,
              ),
            ],
          );
        }

        // Default slider UI
        return Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppColors.gold,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                  thumbColor: AppColors.gold,
                  overlayColor: AppColors.gold.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: value.toDouble().clamp(
                    (param.min ?? 0).toDouble(),
                    (param.max ?? 255).toDouble(),
                  ),
                  min: (param.min ?? 0).toDouble(),
                  max: (param.max ?? 255).toDouble(),
                  onChanged: (v) => _onParamChanged(param.id, v.round()),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                value.round().toString(),
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );

      case ParameterType.bool_:
        final value =
            _paramValues[param.id] as bool? ?? param.defaultValue as bool;
        return _GlowSwitch(
          value: value,
          onChanged: (v) => _onParamChanged(param.id, v),
          activeColor: AppColors.forestGreen,
        );

      case ParameterType.color:
        final colorHex =
            _paramValues[param.id] as String? ?? param.defaultValue as String;
        final color = _parseColor(colorHex);
        return GestureDetector(
          onTap: () => _showColorPicker(param.id, color),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Center(
              child: Text(
                colorHex.toUpperCase(),
                style: TextStyle(
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );

      case ParameterType.palette:
        final value =
            _paramValues[param.id] as int? ?? param.defaultValue as int;
        return SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: paletteNames.length,
            itemBuilder: (context, index) {
              final isSelected = index == value;
              return GestureDetector(
                onTap: () => _onParamChanged(param.id, index),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.forestGreen
                        : AppColors.darkCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.forestGreen
                          : Colors.white24,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    paletteNames[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
        );

      case ParameterType.enumType:
        final value =
            _paramValues[param.id] as int? ?? param.defaultValue as int;
        final options = param.enumValues ?? [];
        return SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final isSelected = index == value;
              return GestureDetector(
                onTap: () => _onParamChanged(param.id, index),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.gold : AppColors.darkCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.gold : Colors.white24,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    options[index],
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return Color(int.parse(hex, radix: 16));
  }

  void _showColorPicker(String paramId, Color currentColor) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text(
          AppLocalizations.of(context)?.colorPickerTitle ?? 'Pick a Color',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: currentColor,
            onColorChanged: (color) {
              // Use new Color API (r/g/b are 0.0-1.0 range)
              final r = (color.r * 255)
                  .round()
                  .toRadixString(16)
                  .padLeft(2, '0');
              final g = (color.g * 255)
                  .round()
                  .toRadixString(16)
                  .padLeft(2, '0');
              final b = (color.b * 255)
                  .round()
                  .toRadixString(16)
                  .padLeft(2, '0');
              final hex = '#$r$g$b'.toUpperCase();
              _onParamChanged(paramId, hex);
            },
            pickersEnabled: const {ColorPickerType.wheel: true},
            enableShadesSelection: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)?.buttonOk ?? 'OK'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Custom Glow Switch
// ============================================================================

class _GlowSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  const _GlowSwitch({
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 28,
        decoration: BoxDecoration(
          color: value ? activeColor.withValues(alpha: 0.3) : Colors.white12,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? activeColor : Colors.white24,
            width: 2,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? activeColor : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
