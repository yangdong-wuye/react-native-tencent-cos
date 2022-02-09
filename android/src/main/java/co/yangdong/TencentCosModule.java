package co.yangdong;

import android.net.Uri;
import android.os.Environment;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import com.tencent.cos.xml.CosXmlService;
import com.tencent.cos.xml.CosXmlServiceConfig;
import com.tencent.cos.xml.CosXmlSimpleService;
import com.tencent.cos.xml.exception.CosXmlClientException;
import com.tencent.cos.xml.exception.CosXmlServiceException;
import com.tencent.cos.xml.listener.CosXmlResultListener;
import com.tencent.cos.xml.model.CosXmlRequest;
import com.tencent.cos.xml.model.CosXmlResult;
import com.tencent.cos.xml.model.object.AbortMultiUploadRequest;
import com.tencent.cos.xml.model.object.CompleteMultiUploadRequest;
import com.tencent.cos.xml.model.object.CompleteMultiUploadResult;
import com.tencent.cos.xml.model.object.InitMultipartUploadRequest;
import com.tencent.cos.xml.model.object.InitMultipartUploadResult;
import com.tencent.cos.xml.model.object.ListPartsRequest;
import com.tencent.cos.xml.model.object.ListPartsResult;
import com.tencent.cos.xml.model.object.UploadPartRequest;
import com.tencent.cos.xml.model.object.UploadPartResult;
import com.tencent.cos.xml.model.tag.CompleteMultipartUploadResult;
import com.tencent.cos.xml.model.tag.InitiateMultipartUpload;
import com.tencent.cos.xml.model.tag.ListParts;
import com.tencent.cos.xml.transfer.COSXMLDownloadTask;
import com.tencent.cos.xml.transfer.TransferConfig;
import com.tencent.cos.xml.transfer.TransferManager;
import com.tencent.qcloud.core.auth.QCloudCredentialProvider;
import com.tencent.qcloud.core.auth.SessionCredentialProvider;
import com.tencent.qcloud.core.auth.ShortTimeCredentialProvider;
import com.tencent.qcloud.core.http.HttpRequest;

import java.io.File;
import java.net.FileNameMap;
import java.net.URL;
import java.net.URLConnection;
import java.util.HashMap;
import java.util.Map;

public class TencentCosModule extends ReactContextBaseJavaModule {

    public static final String NAME = "TencentCosModule";
    private final ReactApplicationContext reactContext;

    private CosXmlSimpleService cosXmlService;
    private CosXmlServiceConfig serviceConfig;
    private TransferManager transferManager;
    private Map<String, COSXMLDownloadTask> downloadTasks;

    public TencentCosModule(ReactApplicationContext reactContext) {
        super(reactContext);
        this.reactContext = reactContext;
    }

    @Override
    @NonNull
    public String getName() {
        return NAME;
    }

    @Nullable
    @Override
    public Map<String, Object> getConstants() {
        final Map<String, Object> constants = new HashMap<>();
        constants.put("DocumentDirectory", 0);
        constants.put("DocumentDirectoryPath", this.getReactApplicationContext().getFilesDir().getAbsolutePath());
        constants.put("TemporaryDirectoryPath", this.getReactApplicationContext().getCacheDir().getAbsolutePath());
        constants.put("PicturesDirectoryPath", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getAbsolutePath());
        constants.put("CachesDirectoryPath", this.getReactApplicationContext().getCacheDir().getAbsolutePath());
        constants.put("DownloadDirectoryPath", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath());
        constants.put("FileTypeRegular", 0);
        constants.put("FileTypeDirectory", 1);

        File externalStorageDirectory = Environment.getExternalStorageDirectory();
        if (externalStorageDirectory != null) {
            constants.put("ExternalStorageDirectoryPath", externalStorageDirectory.getAbsolutePath());
        } else {
            constants.put("ExternalStorageDirectoryPath", null);
        }

        File externalDirectory = this.getReactApplicationContext().getExternalFilesDir(null);
        if (externalDirectory != null) {
            constants.put("ExternalDirectoryPath", externalDirectory.getAbsolutePath());
        } else {
            constants.put("ExternalDirectoryPath", null);
        }

        File externalCachesDirectory = this.getReactApplicationContext().getExternalCacheDir();
        if (externalCachesDirectory != null) {
            constants.put("ExternalCachesDirectoryPath", externalCachesDirectory.getAbsolutePath());
        } else {
            constants.put("ExternalCachesDirectoryPath", null);
        }

        return constants;
    }

    @ReactMethod
    public void initWithPlainSecret(ReadableMap configuration, ReadableMap credentials, Promise promise) {
        if (cosXmlService == null) {
            serviceConfig = initConfiguration(configuration);

            QCloudCredentialProvider credentialProvider = new ShortTimeCredentialProvider(
                    SafeReadableMap.safeGetString(credentials, "secretId"),
                    SafeReadableMap.safeGetString(credentials, "secretKey"),
                    600
            );

            cosXmlService = new CosXmlSimpleService(reactContext, serviceConfig,
                    credentialProvider);

            TransferConfig transferConfig = initTransferConfig();
            transferManager = new TransferManager(cosXmlService, transferConfig);

            downloadTasks = new HashMap<>();
        }

        promise.resolve(null);
    }

    @ReactMethod
    public void initWithSessionCredential(final ReadableMap configuration, final Promise promise) {
        if (cosXmlService == null) {
            serviceConfig = initConfiguration(configuration);
            try {
                // URL 是后台临时密钥服务的地址，如何搭建服务请参考（https://cloud.tencent.com/document/product/436/14048）
                URL url = new URL(SafeReadableMap.safeGetString(configuration, "url"));
                QCloudCredentialProvider credentialProvider = new SessionCredentialProvider(new HttpRequest.Builder<String>()
                        .url(url)
                        .method("GET")
                        .build());
                CosXmlService cosXmlService = new CosXmlService(reactContext, serviceConfig, credentialProvider);
                TransferConfig transferConfig = initTransferConfig();
                transferManager = new TransferManager(cosXmlService, transferConfig);

                downloadTasks = new HashMap<>();

                promise.resolve(null);
            } catch (Exception e) {
                e.printStackTrace();
                promise.reject(e);
            }
        }

    }

    @ReactMethod
    public void getFileInfo(String path, Promise promise) {
        try {
            File file = new File(path);
            if (file.exists()) {
                FileNameMap fileNameMap = URLConnection.getFileNameMap();
                long size = file.length();
                boolean exists = file.exists();
                String mime = fileNameMap.getContentTypeFor(file.getName());
                WritableMap result = Arguments.createMap();
                result.putBoolean("exists", exists);
                result.putString("mime", mime);
                result.putDouble("size", size);
                promise.resolve(result);
            } else {
                promise.reject(new Error("file does not exist "));
            }
        } catch (Exception ex) {
            promise.reject(ex);
        }
    }

    /**
     * 初始化分片上传
     *
     * @param options options
     * @param promise promise
     */
    @ReactMethod
    public void initMultiUpload(final ReadableMap options, final Promise promise) {
        try {
            final String bucket = SafeReadableMap.safeGetString(options, "bucket");
            final String cosPath = SafeReadableMap.safeGetString(options, "cosPath");

            InitMultipartUploadRequest initMultipartUploadRequest =
                    new InitMultipartUploadRequest(bucket, cosPath);
            cosXmlService.initMultipartUploadAsync(initMultipartUploadRequest,
                    new CosXmlResultListener() {
                        @Override
                        public void onSuccess(CosXmlRequest cosXmlRequest, CosXmlResult result) {
                            // 获取uploadId
                            InitiateMultipartUpload multipartUpload = ((InitMultipartUploadResult) result)
                                    .initMultipartUpload;
                            WritableMap params = Arguments.createMap();
                            params.putString("uploadId", multipartUpload.uploadId);
                            params.putString("bucket", multipartUpload.bucket);
                            params.putString("key", multipartUpload.key);

                            promise.resolve(params);
                        }

                        @Override
                        public void onFail(CosXmlRequest cosXmlRequest,
                                           @Nullable CosXmlClientException clientException,
                                           @Nullable CosXmlServiceException serviceException) {
                            promise.reject(clientException != null ? clientException : serviceException);
                        }
                    });
        } catch (Exception ex) {
            promise.reject(ex);
        }
    }


    /**
     * 查询已上传的分块
     * @param options
     * @param promise
     */
    @ReactMethod
    public void listParts(final ReadableMap options, final Promise promise) {
        try {
            final String bucket = SafeReadableMap.safeGetString(options, "bucket");
            final String cosPath = SafeReadableMap.safeGetString(options, "cosPath");
            final String requestId = SafeReadableMap.safeGetString(options, "requestId");

            ListPartsRequest listPartsRequest = new ListPartsRequest(bucket, cosPath,
                    requestId);
            cosXmlService.listPartsAsync(listPartsRequest, new CosXmlResultListener() {
                @Override
                public void onSuccess(CosXmlRequest cosXmlRequest, CosXmlResult result) {
                    ListParts listParts = ((ListPartsResult) result).listParts;

                    WritableArray parts = Arguments.createArray();
                    for (ListParts.Part part : listParts.parts) {
                        WritableMap dic = Arguments.createMap();
                        dic.putDouble("size", Double.parseDouble(part.size));
                        dic.putInt("partNumber", Integer.parseInt(part.partNumber));
                        dic.putString("eTag", part.eTag);
                        parts.pushMap(dic);
                    }
                    promise.resolve(parts);
                }

                @Override
                public void onFail(CosXmlRequest cosXmlRequest,
                                   @Nullable CosXmlClientException clientException,
                                   @Nullable CosXmlServiceException serviceException) {
                    promise.reject(clientException != null ? clientException : serviceException);
                }
            });
        } catch (Exception ex) {
            promise.reject(ex);
        }
    }

    /**
     * 上传分块
     * @param options
     * @param promise
     */
    @ReactMethod
    public void uploadPart(final ReadableMap options, final Promise promise) {
        try {
            String fileUri = SafeReadableMap.safeGetString(options, "fileUri");
            final String bucket = SafeReadableMap.safeGetString(options, "bucket");
            final String cosPath = SafeReadableMap.safeGetString(options, "cosPath");
            final String requestId = SafeReadableMap.safeGetString(options, "requestId");
            final int partNumber = SafeReadableMap.safeGetInt(options, "partNumber");
            final long  offset = (long) SafeReadableMap.safeGetDouble(options, "offset");
            final long sliceSize = 1 * 1024 * 1024;

            File file = new File(fileUri);
            Uri uri = Uri.fromFile(file);

            // 文件总大小
            long totalFileSize = file.length();

            // 剩余文件大小
            long restFileSize = totalFileSize - offset;

            long slice = Math.min(restFileSize, sliceSize);

            UploadPartRequest uploadPartRequest = new UploadPartRequest(bucket, cosPath,
                    partNumber, uri.getPath(), offset, slice, requestId);

            cosXmlService.uploadPartAsync(uploadPartRequest, new CosXmlResultListener() {
                @Override
                public void onSuccess(CosXmlRequest cosXmlRequest, CosXmlResult result) {
                    // 根据文件大小判断是否是最后一段分片
                    boolean last = slice + offset >= totalFileSize;

                    String eTag = ((UploadPartResult) result).eTag;
                    WritableMap dic = Arguments.createMap();
                    dic.putInt("partNumber", partNumber);
                    dic.putDouble("fileSize", totalFileSize);
                    dic.putDouble("partSize", slice);
                    dic.putString("eTag", eTag);
                    dic.putBoolean("last", last);
                    promise.resolve(dic);
                }

                @Override
                public void onFail(CosXmlRequest cosXmlRequest,
                                   @Nullable CosXmlClientException clientException,
                                   @Nullable CosXmlServiceException serviceException) {
                    promise.reject(clientException != null ? clientException : serviceException);
                }
            });
        } catch (Exception ex) {
            promise.reject(ex);
        }
    }


    /**
     * 完成分块上传
     * @param options
     * @param promise
     */
    @ReactMethod
    public void completeUpload(final ReadableMap options, final Promise promise) {
        final String bucket = SafeReadableMap.safeGetString(options, "bucket");
        final String cosPath = SafeReadableMap.safeGetString(options, "cosPath");
        final String requestId = SafeReadableMap.safeGetString(options, "requestId");
        final ReadableArray uploadedParts = SafeReadableMap.safeGetArray(options, "uploadedParts");

        Map<Integer, String> eTags = new HashMap<Integer, String>();
        for (int i = 0; i < uploadedParts.size(); i ++) {
            ReadableMap part = uploadedParts.getMap(i);
            eTags.put(part.getInt("partNumber"), part.getString("eTag"));
        }

        CompleteMultiUploadRequest completeMultiUploadRequest =
                new CompleteMultiUploadRequest(bucket,
                        cosPath, requestId, eTags);

        cosXmlService.completeMultiUploadAsync(completeMultiUploadRequest,
                new CosXmlResultListener() {
                    @Override
                    public void onSuccess(CosXmlRequest cosXmlRequest, CosXmlResult result) {
                        CompleteMultipartUploadResult completeMultiUploadResult =
                                ((CompleteMultiUploadResult) result).completeMultipartUpload;
                        WritableMap dic = Arguments.createMap();
                        dic.putString("key", completeMultiUploadResult.key);
                        dic.putString("eTag", completeMultiUploadResult.eTag);
                        promise.resolve(dic);
                    }

                    @Override
                    public void onFail(CosXmlRequest cosXmlRequest,
                                       @Nullable CosXmlClientException clientException,
                                       @Nullable CosXmlServiceException serviceException) {
                        promise.reject(clientException != null ? clientException : serviceException);
                    }
                });
    }

    /**
     * 取消上传
     * @param options
     * @param promise
     */
    public void cancelUpload(final ReadableMap options, final Promise promise) {
        try {
            final String bucket = SafeReadableMap.safeGetString(options, "bucket");
            final String cosPath = SafeReadableMap.safeGetString(options, "cosPath");
            final String requestId = SafeReadableMap.safeGetString(options, "requestId");

            AbortMultiUploadRequest abortMultiUploadRequest =
                    new AbortMultiUploadRequest(bucket,
                            cosPath, requestId);
            cosXmlService.abortMultiUploadAsync(abortMultiUploadRequest,
                    new CosXmlResultListener() {
                        @Override
                        public void onSuccess(CosXmlRequest cosXmlRequest, CosXmlResult result) {
                            promise.resolve(null);
                        }

                        @Override
                        public void onFail(CosXmlRequest cosXmlRequest,
                                           @Nullable CosXmlClientException clientException,
                                           @Nullable CosXmlServiceException serviceException) {
                            promise.reject(clientException != null ? clientException : serviceException);
                        }
                    });
        } catch (Exception ex) {
            promise.reject(ex);
        }
    }


    /**
     * 下载
     * @param options
     * @param promise
     */
    @ReactMethod
    public void download(ReadableMap options, final Promise promise) {
        try {
            final String bucket = SafeReadableMap.safeGetString(options, "bucket");
            final String cosPath = SafeReadableMap.safeGetString(options, "cosPath");
            final String requestId = SafeReadableMap.safeGetString(options, "requestId");
            final String filePath = SafeReadableMap.safeGetString(options, "filePath");

            File file = new File(filePath);
            String savePathDir = file.getParent();
            String savedFileName = file.getName();

            if (downloadTasks.containsKey(requestId)) {
                COSXMLDownloadTask cosxmlDownloadTask = downloadTasks.get(requestId);
                if (cosxmlDownloadTask != null) {
                    cosxmlDownloadTask.resume();
                }
                promise.resolve(null);
                return;
            }

            COSXMLDownloadTask cosxmlDownloadTask =
                    transferManager.download(reactContext,
                            bucket, cosPath, savePathDir, savedFileName);

            downloadTasks.put(requestId, cosxmlDownloadTask);

            //设置下载进度回调
            cosxmlDownloadTask.setCosXmlProgressListener((complete, target) ->
                    sendProgressMessage(requestId, complete, target));

            //设置返回结果回调
            cosxmlDownloadTask.setCosXmlResultListener(new CosXmlResultListener() {
                @Override
                public void onSuccess(CosXmlRequest request, CosXmlResult result) {
                    COSXMLDownloadTask.COSXMLDownloadTaskResult downloadTaskResult =
                            (COSXMLDownloadTask.COSXMLDownloadTaskResult) result;
                    sendDownloadResultMessage(requestId, downloadTaskResult, null);
                }

                @Override
                public void onFail(CosXmlRequest request,
                                   CosXmlClientException clientException,
                                   CosXmlServiceException serviceException) {
                    sendDownloadResultMessage(requestId, null, clientException != null ? clientException : serviceException);
                }
            });
            promise.resolve(null);
        } catch (Exception e) {
            promise.reject(e);
        }
    }

    /**
     * 暂停下载
     * @param requestId
     * @param promise
     */
    @ReactMethod
    public void pauseDownload(String requestId, final Promise promise) {
        if (downloadTasks.containsKey(requestId)) {
            COSXMLDownloadTask task = downloadTasks.get(requestId);
            if (task != null) {
                task.pause();
            }
        }
        promise.resolve(true);
    }

    /**
     * 取消下载
     * @param requestId
     * @param promise
     */
    @ReactMethod
    public void cancelDownload(String requestId, final Promise promise) {
        if (downloadTasks.containsKey(requestId)) {
            COSXMLDownloadTask task = downloadTasks.get(requestId);
            if (task != null) {
                task.cancel();
            }
        }
        promise.resolve(null);
    }

    private CosXmlServiceConfig initConfiguration(ReadableMap configuration) {
        String region = configuration.getString("region");

        return new CosXmlServiceConfig.Builder()
                .setRegion(region)
                .isHttps(true)
                .builder();
    }

    private TransferConfig initTransferConfig() {
        return  new TransferConfig.Builder().build();
    }

    private void sendProgressMessage(String requestId, long completeBytes, long targetBytes) {
        WritableMap params = Arguments.createMap();
        params.putString("requestId", requestId);
        params.putDouble("processedBytes", completeBytes);
        params.putDouble("targetBytes", targetBytes);
        reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                .emit("COSProgressUpdate", params);
    }

    private void sendDownloadResultMessage(String requestId, COSXMLDownloadTask.COSXMLDownloadTaskResult result, Exception error) {
        WritableMap params = Arguments.createMap();
        params.putString("requestId", requestId);
        if (error == null) {
            params.putBoolean("success", true);
            params.putString("eTag", result.eTag);
        } else {
            params.putBoolean("success", false);
            params.putString("eTag", "");
        }

        reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                .emit("COSDownloadResultUpdate", params);
    }

}
