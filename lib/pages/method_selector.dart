import 'package:flutter/material.dart';
import 'package:hooplab/pages/camera.dart';
import 'package:hooplab/pages/viewer.dart';
import 'package:image_picker/image_picker.dart';

class MethodSelector extends StatefulWidget {
  const MethodSelector({super.key});

  @override
  State<MethodSelector> createState() => _MethodSelectorState();
}

class _MethodSelectorState extends State<MethodSelector> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Constants for consistent styling
  static const double _buttonHeight = 180.0;
  static const double _buttonSpacing = 24.0;
  static const double _borderRadius = 16.0;
  static const double _iconSize = 48.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Start entrance animation
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Prevent multiple simultaneous operations
  Future<void> _handleCameraPress() async {
    if (_isLoading) return;
    
    _setLoading(true);
    
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CameraPage()),
      );
    } finally {
      _setLoading(false);
    }
  }

  // Handle gallery selection with proper error handling
  Future<void> _handleGalleryPress() async {
    if (_isLoading) return;
    
    _setLoading(true);
    
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10), // Optional: limit video length
      );
      
      if (video != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ViewerPage(videoPath: video.path),
          ),
        );
      }
    } catch (e) {
      // Handle errors gracefully
      if (mounted) {
        _showErrorSnackBar('Failed to select video from gallery');
      }
    } finally {
      if (mounted) {
        _setLoading(false);
      }
    }
  }

  void _setLoading(bool loading) {
    if (mounted) {
      setState(() {
        _isLoading = loading;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Choose Method',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Select how you want to add your video',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // Responsive layout
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    
                    if (isWide) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(child: _buildCameraButton(theme)),
                          const SizedBox(width: _buttonSpacing),
                          Expanded(child: _buildGalleryButton(theme)),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildCameraButton(theme),
                          const SizedBox(height: _buttonSpacing),
                          _buildGalleryButton(theme),
                        ],
                      );
                    }
                  },
                ),
                
                if (_isLoading) ...[
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Please wait...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraButton(ThemeData theme) {
    return _MethodButton(
      title: 'Camera',
      subtitle: 'Record a new video',
      icon: Icons.camera_alt_rounded,
      onPressed: _isLoading ? null : _handleCameraPress,
      color: theme.colorScheme.primary,
      isLoading: _isLoading,
    );
  }

  Widget _buildGalleryButton(ThemeData theme) {
    return _MethodButton(
      title: 'Gallery',
      subtitle: 'Choose from library',
      icon: Icons.photo_library_rounded,
      onPressed: _isLoading ? null : _handleGalleryPress,
      color: theme.colorScheme.secondary,
      isLoading: _isLoading,
    );
  }
}

// Extracted custom widget for better reusability and organization
class _MethodButton extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool isLoading;

  const _MethodButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
    required this.color,
    this.isLoading = false,
  });

  @override
  State<_MethodButton> createState() => _MethodButtonState();
}

class _MethodButtonState extends State<_MethodButton> 
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onPressed != null && !widget.isLoading;
    
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => _scaleController.forward() : null,
        onTapUp: isEnabled ? (_) => _scaleController.reverse() : null,
        onTapCancel: () => _scaleController.reverse(),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 180.0,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isEnabled
                  ? [
                      widget.color.withOpacity(0.1),
                      widget.color.withOpacity(0.05),
                    ]
                  : [
                      theme.colorScheme.onSurface.withOpacity(0.05),
                      theme.colorScheme.onSurface.withOpacity(0.02),
                    ],
            ),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: isEnabled 
                  ? widget.color.withOpacity(0.3)
                  : theme.colorScheme.onSurface.withOpacity(0.1),
              width: 2,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isEnabled 
                      ? widget.color.withOpacity(0.1)
                      : theme.colorScheme.onSurface.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 48.0,
                  color: isEnabled 
                      ? widget.color
                      : theme.colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isEnabled 
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isEnabled 
                      ? theme.colorScheme.onSurface.withOpacity(0.7)
                      : theme.colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}