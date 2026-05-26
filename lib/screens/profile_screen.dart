import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/theme_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = StorageService();
  final _nameController = TextEditingController();
  final _schoolController = TextEditingController();
  final _emailController = TextEditingController();
  final _picker = ImagePicker();
  String? _profileImagePath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final name = await _storage.getUserName();
    final school = await _storage.getSchool();
    final email = await _storage.getUserEmail();
    final imagePath = await _storage.getProfileImage();
    
    _nameController.text = name ?? '';
    _schoolController.text = school ?? '';
    _emailController.text = email ?? '';
    
    if (mounted) {
      setState(() => _profileImagePath = imagePath);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      
      if (image != null) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedPath = '${directory.path}/$fileName';
        
        await File(image.path).copy(savedPath);
        
        if (_profileImagePath != null) {
          try {
            await File(_profileImagePath!).delete();
          } catch (_) {}
        }
        
        await _storage.setProfileImage(savedPath);
        
        if (mounted) {
          setState(() => _profileImagePath = savedPath);
        }
        
        if (SupabaseService.instance.isLoggedIn) {
          final avatarUrl = await SupabaseService.instance.uploadAvatar(File(savedPath));
          if (avatarUrl != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Photo uploaded to cloud'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showImagePicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Change Profile Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPickerOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                    isDark: isDark,
                  ),
                  _buildPickerOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                    isDark: isDark,
                  ),
                  if (_profileImagePath != null)
                    _buildPickerOption(
                      icon: Icons.delete_rounded,
                      label: 'Remove',
                      onTap: () async {
                        Navigator.pop(context);
                        if (_profileImagePath != null) {
                          try {
                            await File(_profileImagePath!).delete();
                          } catch (_) {}
                        }
                        await _storage.setProfileImage('');
                        setState(() => _profileImagePath = null);
                        
                        if (SupabaseService.instance.isLoggedIn) {
                          await SupabaseService.instance.removeAvatar();
                        }
                      },
                      isDark: isDark,
                      isDestructive: true,
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? AppColors.error : AppColors.accent;
    
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your name'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    final name = _nameController.text.trim();
    final school = _schoolController.text.trim();
    final email = _emailController.text.trim();
    
    // Save to local storage
    await _storage.setUserName(name);
    await _storage.setSchool(school);
    await _storage.setUserEmail(email);
    
    // Sync to Supabase if logged in
    if (SupabaseService.instance.isLoggedIn) {
      await SupabaseService.instance.updateProfile(
        displayName: name,
        school: school.isNotEmpty ? school : null,
      );
    }
    
    setState(() => _isLoading = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile saved successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _schoolController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            

            GestureDetector(
              onTap: _showImagePicker,
              child: Stack(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(28),
                      image: _profileImagePath != null && _profileImagePath!.isNotEmpty
                          ? DecorationImage(
                              image: FileImage(File(_profileImagePath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _profileImagePath == null || _profileImagePath!.isEmpty
                        ? Center(
                            child: Text(
                              _nameController.text.isNotEmpty 
                                  ? _nameController.text[0].toUpperCase() 
                                  : 'S',
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent,
                              ),
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            Text(
              'Tap to change photo',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
              ),
            ),
            
            const SizedBox(height: 32),
            

            _buildTextField(
              controller: _nameController,
              label: 'Full Name',
              icon: Icons.person_outline_rounded,
              isDark: isDark,
            ),
            
            const SizedBox(height: 16),
            

            _buildTextField(
              controller: _schoolController,
              label: 'School / University',
              icon: Icons.school_outlined,
              isDark: isDark,
            ),
            
            const SizedBox(height: 16),
            

            _buildTextField(
              controller: _emailController,
              label: 'Email (optional)',
              icon: Icons.email_outlined,
              isDark: isDark,
              keyboardType: TextInputType.emailAddress,
            ),
            
            const SizedBox(height: 40),
            

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Save Profile',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        keyboardType: keyboardType,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          ),
          prefixIcon: Icon(icon, color: AppColors.accent),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }
}
