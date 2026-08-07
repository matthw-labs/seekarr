import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';

class AddTorrentButton extends ConsumerWidget {
  const AddTorrentButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(Icons.add_rounded, color: AppColors.qbittorrent),
      onPressed: () => _showAddTorrentSheet(context, ref),
      tooltip: 'Add Torrent',
    );
  }

  void _showAddTorrentSheet(BuildContext context, WidgetRef ref) {
    final urlController = TextEditingController();
    final categoryController = TextEditingController();
    final savePathController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final pickedFilesNotifier = ValueNotifier<List<PlatformFile>>([]);

    AppBottomSheet.show<void>(
      context: context,
      title: 'Add torrent',
      icon: Icons.add_link_rounded,
      accent: AppColors.qbittorrent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          return Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Magnet / URL',
                    hintText: 'magnet:?xt=urn:btih:...',
                  ),
                  onChanged: (_) => setModalState(() {}),
                  validator: (v) {
                    if (pickedFilesNotifier.value.isNotEmpty) return null;
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Required';
                    final isMagnet = value.toLowerCase().startsWith('magnet:');
                    final isHttp =
                        value.toLowerCase().startsWith('http://') ||
                        value.toLowerCase().startsWith('https://');
                    if (!isMagnet && !isHttp) {
                      return 'Enter a magnet link or an http(s) URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                ValueListenableBuilder<List<PlatformFile>>(
                  valueListenable: pickedFilesNotifier,
                  builder: (context, files, _) {
                    if (files.isEmpty) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.attach_file_rounded, size: 18),
                          label: const Text('Pick .torrent files'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.qbittorrent,
                            side: BorderSide(color: AppColors.qbittorrent),
                          ),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              allowMultiple: true,
                              type: FileType.custom,
                              allowedExtensions: const ['torrent'],
                              withData: true,
                            );
                            if (result != null && result.files.isNotEmpty) {
                              pickedFilesNotifier.value = result.files;
                              setModalState(() {});
                            }
                          },
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...files.map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.description_rounded,
                                  size: 16,
                                  color: AppColors.qbittorrent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'Remove',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    pickedFilesNotifier.value = files
                                        .where((x) => x != f)
                                        .toList(growable: false);
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add more files'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.qbittorrent,
                          ),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              allowMultiple: true,
                              type: FileType.custom,
                              allowedExtensions: const ['torrent'],
                              withData: true,
                            );
                            if (result != null && result.files.isNotEmpty) {
                              pickedFilesNotifier.value = [
                                ...files,
                                ...result.files,
                              ];
                              setModalState(() {});
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: savePathController,
                  decoration: const InputDecoration(
                    labelText: 'Save Path (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.qbittorrent,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final service = ref.read(qbittorrentServiceProvider);
                      final files = pickedFilesNotifier.value;
                      final category = categoryController.text.trim().isEmpty
                          ? null
                          : categoryController.text.trim();
                      final savePath = savePathController.text.trim().isEmpty
                          ? null
                          : savePathController.text.trim();

                      if (files.isNotEmpty) {
                        final multipart = <MultipartFile>[];
                        for (final f in files) {
                          if (f.bytes != null) {
                            multipart.add(
                              MultipartFile.fromBytes(
                                f.bytes!,
                                filename: f.name,
                              ),
                            );
                          }
                        }
                        await service.addTorrentFiles(
                          multipart,
                          category: category,
                          savePath: savePath,
                        );
                      } else {
                        await service.addTorrentUrl(
                          urlController.text.trim(),
                          category: category,
                          savePath: savePath,
                        );
                      }
                      ref.invalidate(torrentsProvider);
                      Navigator.of(ctx2).pop();
                      if (context.mounted) {
                        SnackBarHelper.success(
                          context,
                          'Torrent added successfully',
                        );
                      }
                    } catch (e) {
                      SnackBarHelper.error(ctx2, 'Failed to add torrent: $e');
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Add Torrent',
                        style: Theme.of(
                          ctx2,
                        ).textTheme.labelLarge!.weight(FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
