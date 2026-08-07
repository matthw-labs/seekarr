import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';

/// Shared in-memory fake [ApiClient] used by service tests.
///
/// Prefer configuring a single response via [getResponseData] / [postResponseData] /
/// etc. For multi-call scenarios, use [getResponseQueue] which is consumed FIFO
/// (falling back to [getResponseData] when empty).
class FakeApiClient extends ApiClient {
  FakeApiClient() : super(baseUrl: 'https://example.com', apiKey: 'key');

  // Canned responses
  dynamic getResponseData;
  dynamic postResponseData;
  dynamic putResponseData;
  dynamic deleteResponseData;

  /// Optional FIFO queue of GET responses. When non-empty, each call to [get]
  /// consumes the head; when empty, [getResponseData] is returned instead.
  final List<dynamic> getResponseQueue = [];

  // Canned exceptions
  Object? getException;
  Object? postException;
  Object? putException;
  Object? deleteException;

  // Recorded calls
  String? lastGetPath;
  Map<String, dynamic>? lastGetQueryParameters;
  CancelToken? lastGetCancelToken;
  Duration? lastGetReceiveTimeout;
  int getCallCount = 0;

  String? lastPostPath;
  dynamic lastPostData;
  Map<String, dynamic>? lastPostQueryParameters;
  Duration? lastPostReceiveTimeout;
  int postCallCount = 0;

  String? lastPutPath;
  dynamic lastPutData;
  Map<String, dynamic>? lastPutQueryParameters;
  int putCallCount = 0;

  String? lastPatchPath;
  dynamic lastPatchData;
  Map<String, dynamic>? lastPatchQueryParameters;
  dynamic patchResponseData;
  Object? patchException;
  int patchCallCount = 0;

  String? lastDeletePath;
  dynamic lastDeleteData;
  Map<String, dynamic>? lastDeleteQueryParameters;
  int deleteCallCount = 0;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    lastGetPath = path;
    lastGetQueryParameters = queryParameters;
    lastGetCancelToken = cancelToken;
    lastGetReceiveTimeout = receiveTimeout;
    getCallCount++;

    if (getException != null) throw getException!;

    final data = getResponseQueue.isNotEmpty
        ? getResponseQueue.removeAt(0)
        : getResponseData;

    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: data,
    );
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    lastPostPath = path;
    lastPostData = data;
    lastPostQueryParameters = queryParameters;
    lastPostReceiveTimeout = receiveTimeout;
    postCallCount++;

    if (postException != null) throw postException!;

    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: postResponseData,
    );
  }

  @override
  Future<Response<dynamic>> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    lastPutPath = path;
    lastPutData = data;
    lastPutQueryParameters = queryParameters;
    putCallCount++;

    if (putException != null) throw putException!;

    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: putResponseData,
    );
  }

  @override
  Future<Response<dynamic>> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    lastPatchPath = path;
    lastPatchData = data;
    lastPatchQueryParameters = queryParameters;
    patchCallCount++;

    if (patchException != null) throw patchException!;

    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: patchResponseData,
    );
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    lastDeletePath = path;
    lastDeleteData = data;
    lastDeleteQueryParameters = queryParameters;
    deleteCallCount++;

    if (deleteException != null) throw deleteException!;

    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: deleteResponseData,
    );
  }
}
