export type InitListener = (requestId: string) => void;

export interface ProgressEvent {
  requestId: string;
  processedBytes: number;
  targetBytes: number;
}

export type ProgressListener = (
  processedBytes: number,
  targetBytes: number
) => void;

export type ResultListener = (error?: Error) => void;

export interface OptionListeners {
  initListener?: InitListener;
  progressListener?: ProgressListener;
  resultListener?: ResultListener;
}

export interface DownloadResultEvent {
  requestId: string;
  success: boolean;
  eTag?: string;
}

export interface FileInfo {
  exists: boolean;
  size: number;
  mime: string;
  md5: number;
}

export interface InitiateMultipartUploadRequest {
  bucket: string;
  cosPath: string;
}

export interface InitiateMultipartUpload {
  uploadId: string;
  bucket: string;
  key: string;
}

export interface UploadObjectRequest {
  requestId?: string;
  bucket: string;
  cosPath: string;
  fileUri: string;
}

export interface ListPartsRequest {
  requestId: string;
  bucket: string;
  cosPath: string;
}

export interface UploadPartRequest {
  requestId?: string;
  bucket: string;
  cosPath: string;
  fileUri: string;
  partNumber: number;
  offset: number;
}

export interface CompleteUploadRequest {
  requestId: string;
  bucket: string;
  cosPath: string;
  uploadedParts: FilePart[];
}

export interface UploadObjectResult {
  eTag: string;
  size: number;
}

export interface CancelUploadRequest {
  bucket: string;
  cosPath: string;
  requestId: string;
}

export interface DownloadObjectRequest {
  requestId?: string;
  bucket: string;
  cosPath: string;
  filePath: string;
}

export interface Configuration {
  region: string;
  divisionForUpload?: number;
  sliceSizeForUpload?: number;
}

export interface Secret {
  secretId: string;
  secretKey: string;
}

export interface SessionCredential {
  tmpSecretId: string;
  tmpSecretKey: string;
  expiredTime: string;
  sessionToken: string;
}

export interface FilePart {
  partNumber: number;
  size: number;
  eTag: number;
}

export interface UploadPartResult {
  partNumber: number;
  eTag: number;
  partSize: number;
  fileSize: number;
  last: boolean;
}

export type TencentCosType = {
  /**
   * ?????????????????????
   * @param configurations
   * @param credential
   */
  initWithPlainSecret(
    configurations: Configuration,
    credential: Secret
  ): Promise<void>;

  /**
   * ???????????????????????????
   * @param configurations
   */
  initWithSessionCredential(configurations: Configuration): Promise<void>;

  /**
   * ?????????????????????
   * @param request
   */
  initMultiUpload(
    request: InitiateMultipartUploadRequest
  ): Promise<InitiateMultipartUpload>;

  /**
   * ?????????????????????
   * @param request
   */
  listParts(request: ListPartsRequest): Promise<FilePart[]>;

  /**
   * ????????????
   * @param request
   */
  uploadPart(request: UploadPartRequest): Promise<UploadPartResult>;

  /**
   * ??????????????????
   * @param request
   */
  completeUpload(request: CompleteUploadRequest): Promise<UploadObjectResult>;

  /**
   * ????????????
   * @param request
   */
  cancelUpload(request: CancelUploadRequest): Promise<void>;

  /**
   * ??????
   * @param request
   */
  download(request: DownloadObjectRequest): Promise<void>;

  /**
   * ????????????
   * @param requestId
   */
  pauseDownload(requestId: string): Promise<void>;

  /**
   * ????????????
   * @param requestId
   */
  cancelDownload(requestId: string): Promise<void>;

  getFileInfo(path: string): Promise<FileInfo>;
};
