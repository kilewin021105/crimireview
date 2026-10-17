import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/offline_sync_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';

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
  String? _avatarUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final name = await _storage.getUserName();
    final school = await _storage.getSchool();
    // Signed in: always the real sign-in email (it can't be changed here).
    final email = _signedIn
        ? SupabaseService.instance.currentUser?.email
        : await _storage.getUserEmail();
    final imagePath = await _storage.getProfileImage();
    final avatarUrl = await _storage.getAvatarUrl();

    _nameController.text = name;
    _schoolController.text = school ?? '';
    _emailController.text = email ?? '';

    if (mounted) {
      setState(() {
        _profileImagePath = imagePath;
        _avatarUrl = avatarUrl;
      });
    }
  }

  bool get _signedIn => SupabaseService.instance.isLoggedIn;

  bool get _hasPhoto =>
      (_profileImagePath != null && _profileImagePath!.isNotEmpty) ||
      (_avatarUrl != null && _avatarUrl!.isNotEmpty);

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

        if (_profileImagePath != null && _profileImagePath!.isNotEmpty) {
          try {
            await File(_profileImagePath!).delete();
          } catch (_) {}
        }

        await _storage.setProfileImage(savedPath);

        if (mounted) {
          setState(() => _profileImagePath = savedPath);
        }

        if (SupabaseService.instance.isLoggedIn) {
          final avatarUrl = await OfflineSyncService.instance.uploadAvatarOrQueue(savedPath);
          if (avatarUrl != null && mounted) {
            showAppSnack(context, 'Photo uploaded to the cloud', tone: BannerTone.success);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(context, "Couldn't use that photo. Please try another one.", tone: BannerTone.danger);
      }
    }
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        final text = sheetContext.textStyles;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text('Profile photo', style: text.titleLarge),
                ),
                AppListGroup(
                  children: [
                    AppListTile(
                      icon: Icons.photo_camera_rounded,
                      title: 'Take a photo',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                    AppListTile(
                      icon: Icons.photo_library_rounded,
                      title: 'Choose from gallery',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                    if (_hasPhoto)
                      AppListTile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Remove photo',
                        destructive: true,
                        showChevron: false,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          if (_profileImagePath != null && _profileImagePath!.isNotEmpty) {
                            try {
                              await File(_profileImagePath!).delete();
                            } catch (_) {}
                          }
                          await _storage.setProfileImage('');
                          await _storage.setAvatarUrl(null);
                          if (!mounted) return;
                          setState(() {
                            _profileImagePath = null;
                            _avatarUrl = null;
                          });

                          if (SupabaseService.instance.isLoggedIn) {
                            await OfflineSyncService.instance.removeAvatarOrQueue();
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      showAppSnack(context, 'Please enter your name', tone: BannerTone.danger);
      return;
    }

    setState(() => _isLoading = true);

    final name = _nameController.text.trim();
    final school = _schoolController.text.trim();
    final email = _emailController.text.trim();

    // Save to local storage
    await _storage.setUserName(name);
    await _storage.setSchool(school);
    if (!_signedIn) await _storage.setUserEmail(email);

    // Sync to Supabase if logged in. An empty school is sent as '' so that
    // clearing the field clears it online too (null would mean "no change").
    if (_signedIn) {
      await OfflineSyncService.instance.saveProfileDetailsOrQueue(
        displayName: name,
        school: school,
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    showAppSnack(context, 'Profile saved', tone: BannerTone.success);
    Navigator.pop(context);
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
    final p = context.palette;
    final text = context.textStyles;
    final padding = Responsive.horizontalPadding(context);
    final name = _nameController.text.trim();
    final school = _schoolController.text.trim();

    return Scaffold(
      appBar: const AppTopBar(title: 'Edit profile'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, 24),
              child: ContentWidth(
                maxWidth: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _showImagePicker,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                UserAvatar(
                                  name: name.isEmpty ? 'Student' : name,
                                  imagePath: _profileImagePath,
                                  imageUrl: _avatarUrl,
                                  size: 104,
                                  ring: true,
                                ),
                                Positioned(
                                  bottom: 2,
                                  right: -2,
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: p.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: p.surface, width: 3),
                                    ),
                                    child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 17),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            name.isEmpty ? 'Your name' : name,
                            style: text.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            school.isEmpty ? 'Add your school below' : school,
                            style: text.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _showImagePicker,
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            label: Text(_hasPhoto ? 'Change photo' : 'Add a photo'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppTextField(
                      controller: _nameController,
                      label: 'Full name',
                      hint: 'Juan Dela Cruz',
                      icon: Icons.person_outline_rounded,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _schoolController,
                      label: 'School / University',
                      hint: 'Where you studied Criminology',
                      icon: Icons.school_outlined,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _emailController,
                      label: _signedIn ? 'Sign-in email' : 'Email (optional)',
                      hint: 'you@example.com',
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_signedIn,
                      helperText: _signedIn ? 'The email you sign in with. It can’t be changed here.' : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: ContentWidth(
                  maxWidth: 560,
                  child: PrimaryButton(
                    label: 'Save profile',
                    loading: _isLoading,
                    onPressed: _saveProfile,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
