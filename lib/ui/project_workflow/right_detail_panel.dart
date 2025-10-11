import 'package:flutter/material.dart';

import '../../models/site.dart';

class RightDetailPanel extends StatefulWidget {
  const RightDetailPanel({
    super.key,
    required this.site,
    required this.projectDefaultStacks,
    required this.onMetadataChanged,
  });

  final SiteRecord site;
  final int projectDefaultStacks;
  final void Function({
    double? power,
    int? stacks,
    SoilType? soil,
    MoistureLevel? moisture,
  }) onMetadataChanged;

  @override
  State<RightDetailPanel> createState() => _RightDetailPanelState();
}

class _RightDetailPanelState extends State<RightDetailPanel> {
  late TextEditingController _powerController;
  late int _stacks;
  late SoilType _soil;
  late MoistureLevel _moisture;

  @override
  void initState() {
    super.initState();
    _powerController = TextEditingController(
      text: widget.site.powerMilliAmps.toStringAsFixed(1),
    );
    _stacks = widget.site.stacks;
    _soil = widget.site.soil;
    _moisture = widget.site.moisture;
  }

  @override
  void didUpdateWidget(RightDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site) {
      _powerController.text = widget.site.powerMilliAmps.toStringAsFixed(1);
      _stacks = widget.site.stacks;
      _soil = widget.site.soil;
      _moisture = widget.site.moisture;
    }
  }

  @override
  void dispose() {
    _powerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Site details',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Site ID: ${widget.site.siteId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            _buildPowerField(theme),
            const SizedBox(height: 16),
            _buildStacksField(theme),
            const SizedBox(height: 16),
            _buildSoilField(theme),
            const SizedBox(height: 16),
            _buildMoistureField(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerField(ThemeData theme) {
    return TextField(
      controller: _powerController,
      decoration: InputDecoration(
        labelText: 'Transmitter power (mA)',
        helperText: 'Typical: 0.5–2.0 mA',
        suffixText: 'mA',
        border: const OutlineInputBorder(),
      ),
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: false),
      onSubmitted: _handlePowerSubmitted,
      onEditingComplete: () => _handlePowerSubmitted(_powerController.text),
    );
  }

  Widget _buildStacksField(ThemeData theme) {
    final options = List<int>.generate(18, (index) => index + 1);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Stack count',
        border: const OutlineInputBorder(),
        helperText: 'Project default: ${widget.projectDefaultStacks}',
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _stacks.clamp(1, options.last),
          isExpanded: true,
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _stacks = value;
            });
            widget.onMetadataChanged(stacks: value);
          },
          items: [
            for (final value in options)
              DropdownMenuItem<int>(
                value: value,
                child: Text('$value stacks'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoilField(ThemeData theme) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Soil type',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SoilType>(
          value: _soil,
          isExpanded: true,
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _soil = value;
            });
            widget.onMetadataChanged(soil: value);
          },
          items: [
            for (final value in SoilType.values)
              DropdownMenuItem<SoilType>(
                value: value,
                child: Text(value.label),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoistureField(ThemeData theme) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Moisture level',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MoistureLevel>(
          value: _moisture,
          isExpanded: true,
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _moisture = value;
            });
            widget.onMetadataChanged(moisture: value);
          },
          items: [
            for (final value in MoistureLevel.values)
              DropdownMenuItem<MoistureLevel>(
                value: value,
                child: Text(value.label),
              ),
          ],
        ),
      ),
    );
  }

  void _handlePowerSubmitted(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed.isNaN || parsed.isNegative) {
      _powerController.text = widget.site.powerMilliAmps.toStringAsFixed(1);
      return;
    }
    _powerController.text = parsed.toStringAsFixed(1);
    widget.onMetadataChanged(power: parsed);
  }
}
