import { NativeEventEmitter, NativeModules } from 'react-native';
import { v4 as uuidv4 } from 'uuid';
import type { Token } from './token';
import type {
  CancelUploadRequest,
  Configuration,
  CosXmlModuleType,
  DownloadObjectRequest,
  DownloadResultEvent,
  FileInfo,
  OptionListeners,
  ProgressEvent,
  ProgressListener,
  ResultListener,
  Secret,
  UploadObjectRequest,
} from './types';

const { CosXmlModule } = NativeModules;

const cosModule = CosXmlModule as CosXmlModuleType;

class CosXmlService {
  static instance: CosXmlService;

  static getInstance() {
    if (!CosXmlService.instance) {
      CosXmlService.instance = new CosXmlService();
      return CosXmlService.instance;
    }
    return CosXmlService.instance;
  }

  private progressListeners: Map<string, ProgressListener>;
  private downloadResultListeners: Map<string, ResultListener>;

  private emitter: NativeEventEmitter;
  private initialized: boolean = false;

  constructor() {
    this.progressListeners = new Map();
    this.downloadResultListeners = new Map();

    this.emitter = new NativeEventEmitter(CosXmlModule);

    this.emitter.addListener('COSProgressUpdate', (event: ProgressEvent) => {
      const { requestId, processedBytes, targetBytes } = event;
      if (this.progressListeners.has(requestId)) {
        this.progressListeners.get(requestId)!(
          processedBytes >= targetBytes ? targetBytes : processedBytes,
          targetBytes
        );
      }
    });

    this.emitter.addListener(
      'COSDownloadResultUpdate',
      (event: DownloadResultEvent) => {
        const { requestId, success } = event;
        if (this.downloadResultListeners.has(requestId)) {
          this.downloadResultListeners.get(requestId)!(
            success ? undefined : new Error()
          );
        }
      }
    );
  }

  get MainBundlePath(): string {
    return CosXmlModule.MainBundlePath;
  }
  get CachesDirectoryPath(): string {
    return CosXmlModule.CachesDirectoryPath;
  }
  get ExternalCachesDirectoryPath(): string {
    return CosXmlModule.ExternalCachesDirectoryPath;
  }
  get DocumentDirectoryPath(): string {
    return CosXmlModule.DocumentDirectoryPath;
  }
  get DownloadDirectoryPath(): string {
    return CosXmlModule.DownloadDirectoryPath;
  }
  get ExternalDirectoryPath(): string {
    return CosXmlModule.ExternalDirectoryPath;
  }
  get ExternalStorageDirectoryPath(): string {
    return CosXmlModule.ExternalStorageDirectoryPath;
  }
  get TemporaryDirectoryPath(): string {
    return CosXmlModule.TemporaryDirectoryPath;
  }
  get LibraryDirectoryPath(): string {
    return CosXmlModule.LibraryDirectoryPath;
  }
  get PicturesDirectoryPath(): string {
    return CosXmlModule.PicturesDirectoryPath;
  }
  get FileProtectionKeys(): string {
    return CosXmlModule.FileProtectionKeys;
  }

  getFileInfo(path: string): Promise<FileInfo> {
    return CosXmlModule.getFileInfo(path);
  }

  initWithPlainSecret(
    configurations: Configuration,
    credential: Secret
  ): Promise<void> {
    if (!this.initialized) {
      this.initialized = true;
      return cosModule.initWithPlainSecret(
        {
          divisionForUpload: 1024 * 1024,
          sliceSizeForUpload: 1024 * 1024,
          ...configurations,
        },
        credential
      );
    }
    return Promise.resolve();
  }

  initWithSessionCredential(configurations: Configuration): Promise<void> {
    if (!this.initialized) {
      this.initialized = true;
      return cosModule.initWithSessionCredential({
        divisionForUpload: 1024 * 1024,
        sliceSizeForUpload: 1024 * 1024,
        ...configurations,
      });
    }
    return Promise.resolve();
  }

  async upload(
    request: UploadObjectRequest,
    listeners: OptionListeners,
    token?: Token
  ): Promise<void> {
    const { initListener, progressListener, resultListener } = listeners;
    try {
      let { requestId } = request;

      if (!requestId) {
        const { uploadId } = await cosModule.initMultiUpload({
          bucket: request.bucket,
          cosPath: request.cosPath,
        });
        requestId = uploadId;
        !!initListener && initListener(uploadId);
      }

      // 列出已上传的分片
      const uploadedParts = await cosModule.listParts({
        requestId,
        bucket: request.bucket,
        cosPath: request.cosPath,
      });

      let last = false;
      let partNumber = uploadedParts.length + 1;
      while (!last) {
        if (token && token.pause) {
          break;
        }

        // 计算已上传的大小
        const offset = uploadedParts.reduce(
          (total, next) => total + next.size,
          0
        );

        const part = await cosModule.uploadPart({
          ...request,
          requestId,
          partNumber,
          offset,
        });

        uploadedParts.push({
          partNumber,
          size: part.partSize,
          eTag: part.eTag,
        });
        !!progressListener &&
          progressListener(offset + part.partSize, part.fileSize);
        last = part.last;
        partNumber++;
      }

      if (last) {
        await cosModule.completeUpload({
          ...request,
          requestId,
          uploadedParts,
        });
        !!resultListener && resultListener();
      }
    } catch (error) {
      !!resultListener && resultListener(error as Error);
      throw error;
    }
  }

  cancelUpload(request: CancelUploadRequest) {
    return cosModule.cancelUpload(request);
  }

  async download(
    request: DownloadObjectRequest,
    listeners: OptionListeners
  ): Promise<void> {
    let { requestId } = request;
    if (!requestId) {
      requestId = uuidv4();
    }
    const { initListener, progressListener, resultListener } = listeners;

    try {
      !!initListener && initListener(requestId);
      !!progressListener &&
        this.progressListeners.set(requestId, progressListener);
      !!resultListener &&
        this.downloadResultListeners.set(requestId, resultListener);
      await cosModule.download({ ...request, requestId });
    } catch (err) {
      !!resultListener && resultListener(err as Error);
      this.removeListener(requestId);
      throw err;
    }
  }

  async pauseDownload(requestId: string) {
    this.removeListener(requestId);
    await cosModule.pauseDownload(requestId);
  }

  async cancelDownload(requestId: string) {
    this.removeListener(requestId);
    await cosModule.cancelDownload(requestId);
  }

  private removeListener(requestId: string) {
    if (requestId) {
      this.progressListeners.delete(requestId);
      this.downloadResultListeners.delete(requestId);
    }
  }
}

export const CosXml = CosXmlService.getInstance();

export * from './token';
export * from './types';
