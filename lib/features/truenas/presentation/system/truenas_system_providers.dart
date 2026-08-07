import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/truenas/domain/models/credentials.dart';
import 'package:cupola/features/truenas/domain/models/network.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

final truenasGeneralConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getGeneralConfig();
    });

final truenasAdvancedConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getAdvancedConfig();
    });

final truenasMailConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getMailConfig();
    });

final truenasUpdateStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).checkUpdateAvailable();
    });

final truenasNtpServersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getNtpServers();
    });

final truenasCertificatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getCertificates();
    });

final truenasAlertServicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getAlertServices();
    });

final truenasNetworkConfigProvider =
    FutureProvider.autoDispose<TrueNasNetworkConfig>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasNetworkApiProvider).getConfig();
    });

final truenasInterfacesProvider =
    FutureProvider.autoDispose<List<TrueNasInterface>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasNetworkApiProvider).getInterfaces();
    });

final truenasUsersProvider = FutureProvider.autoDispose<List<TrueNasUser>>((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasCredentialsApiProvider).getUsers();
});

final truenasGroupsProvider = FutureProvider.autoDispose<List<TrueNasGroup>>((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasCredentialsApiProvider).getGroups();
});
