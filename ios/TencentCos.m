#import "TencentCos.h"
#import <QCloudCore/QCloudCore.h>
#import <QCloudcore/NSObject+QCloudModel.h>
#import <QCloudCOSXML/QCloudCOSXMLTransfer.h>
#import <QCloudCOSXML/QCloudCOSXMLDownloadObjectRequest.h>
#import <QCloudCOSXML/QCloudMultipartInfo.h>
#import <QCloudCOSXML/QCloudCompleteMultipartUploadInfo.h>
#import <React/RCTConvert.h>
#import <Photos/Photos.h>

@interface TencentCos() <QCloudSignatureProvider, QCloudCredentailFenceQueueDelegate>
@property (nonatomic, strong) QCloudCredentailFenceQueue* credentialFenceQueue;

@end

static BOOL initial;
NSString* const PROGRESS_EVENT = @"COSProgressUpdate";
NSString* const DOWNLOAD_RESULT_EVENT = @"COSDownloadResultUpdate";


@implementation TencentCos {
  dispatch_group_t g;
  QCloudCredential* sessionCredential;
  
  NSString* secretId;
  NSString* secretKey;
  
  NSMutableDictionary<NSString*, QCloudCOSXMLDownloadObjectRequest*> * downloadTasks;
}
- (id)init {
  self = [super init];
  if (self) {
//    self.initial = false;
  }
  return self;
}


RCT_EXPORT_MODULE()
- (NSArray<NSString *> *)supportedEvents {
  return @[PROGRESS_EVENT, DOWNLOAD_RESULT_EVENT];
}

/**
 用固定密钥初始化
 */
RCT_REMAP_METHOD(initWithPlainSecret, initWithConfig: (NSDictionary *)config plainSecret:(NSDictionary*)credential resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  if (!initial) {
	[self initService:config];

	secretId = [credential objectForKey:@"secretId"];
	secretKey = [credential objectForKey:@"secretKey"];
   
	initial = YES;
  }
  
  resolve(nil);
}

/**
 用临时密钥回调初始化
 */
RCT_REMAP_METHOD(initWithSessionCredentialCallback, initWithConfig:(NSDictionary*)config resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  if (!initial) {
	[self initService:config];
	
   initial = YES;
  }
  
  resolve(nil);
}

// 初始化分块上传
RCT_EXPORT_METHOD(initMultiUpload:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSString *bucket = [options objectForKey:@"bucket"];
  NSString *cosPath = [options objectForKey:@"cosPath"];

  QCloudInitiateMultipartUploadRequest* initRequest = [QCloudInitiateMultipartUploadRequest new];
  // 存储桶名称，由BucketName-Appid 组成，可以在COS控制台查看 https://console.cloud.tencent.com/cos5/bucket
  initRequest.bucket = bucket;
  // 对象键，是对象在 COS 上的完整路径，如果带目录的话，格式为 "video/xxx/movie.mp4"
  initRequest.object = cosPath;
//  // 将作为对象的元数据返回
//  initRequest.cacheControl = @"cacheControl";
//  initRequest.contentDisposition = @"contentDisposition";
//  // 定义 Object 的 ACL 属性。有效值：private，public-read-write，public-read；默认值：private
//  initRequest.accessControlList = @"public";
//  // 赋予被授权者读的权限。
//  initRequest.grantRead = @"grantRead";
//  // 赋予被授权者全部权限
//  initRequest.grantFullControl = @"grantFullControl";
  [initRequest setFinishBlock:^(QCloudInitiateMultipartUploadResult* outputObject,
								NSError *error) {
	if (error) {
	  reject([@(error.code) stringValue], error.localizedDescription, error);
	} else {
	  // 获取分块上传的 uploadId，后续的上传都需要这个 ID，请保存以备后续使用
	  NSMutableDictionary* dic = [NSMutableDictionary new];
	  [dic setObject:outputObject.uploadId forKey:@"uploadId"];
	  [dic setObject:outputObject.bucket forKey:@"bucket"];
	  [dic setObject:outputObject.key forKey:@"key"];
	  resolve([dic copy]);
	}
  }];

  [[QCloudCOSXMLService defaultCOSXML] InitiateMultipartUpload:initRequest];
}

RCT_EXPORT_METHOD(getFileInfo:(NSString *)path resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSFileManager *defaultManager = [NSFileManager defaultManager];
  BOOL exists = [defaultManager fileExistsAtPath:path];
  
  if (exists) {
	NSString *mime = [self getMimeType:path];
	NSError *error = nil;
	long size = [[defaultManager attributesOfItemAtPath:path error:&error] fileSize];
	
	if (error != nil) {
	  reject([@(error.code) stringValue], error.localizedDescription, error);
	} else {
	  NSMutableDictionary* dic = [NSMutableDictionary new];
	  [dic setObject:@(exists) forKey:@"exists"];
	  [dic setObject:mime forKey:@"mime"];
	  [dic setObject:@(size) forKey:@"size"];
	  resolve([dic copy]);
	}
  } else {
	reject(@"error", @"file does not exist ", nil);
  }
}

RCT_EXPORT_METHOD(listParts:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSString *bucket = [options objectForKey:@"bucket"];
  NSString *cosPath = [options objectForKey:@"cosPath"];
  NSString *requestId = [options objectForKey:@"requestId"];
  
  if (requestId) {
	//.cssg-snippet-body-start:[objc-list-parts]
	QCloudListMultipartRequest* request = [QCloudListMultipartRequest new];
	
	// 对象键，是对象在 COS 上的完整路径，如果带目录的话，格式为 "dir1/object1"
	request.object = cosPath;
	
	// 存储桶名称，格式为 BucketName-APPID
	request.bucket = bucket;
	
	// 在初始化分块上传的响应中，会返回一个唯一的描述符（upload ID）
	request.uploadId = requestId;
	
	[request setFinishBlock:^(QCloudListPartsResult * _Nonnull result,
							  NSError * _Nonnull error) {
	  if (error) {
		reject([@(error.code) stringValue], error.localizedDescription, error);
	  } else {
		// 从 result 中获取已上传分块信息
		// 用来表示每一个块的信息
		NSArray<QCloudMultipartUploadPart*> *parts = result.parts;
		NSMutableArray *list = [NSMutableArray array];
		for (int i =0; i < parts.count; i ++) {
		  NSMutableDictionary* dic = [NSMutableDictionary new];
		  [dic setObject:[NSNumber numberWithLongLong:parts[i].size] forKey:@"size"];
		  [dic setObject:parts[i].partNumber forKey:@"partNumber"];
		  [dic setObject:parts[i].eTag forKey:@"eTag"];
		  [list addObject:dic];
		}
		
		resolve([list copy]);
	  }
	}];
	
	[[QCloudCOSXMLService defaultCOSXML] ListMultipart:request];
  }
}

RCT_EXPORT_METHOD(uploadPart:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSString *fileUri = [options objectForKey:@"fileUri"];
  NSString *bucket = [options objectForKey:@"bucket"];
  NSString *cosPath = [options objectForKey:@"cosPath"];
  NSString *requestId = [options objectForKey:@"requestId"];
  int partNumber = [[options objectForKey:@"partNumber"] intValue];
  long offset = [[options objectForKey:@"offset"] longLongValue];
  
  if ([fileUri hasPrefix:@"file://"] || [fileUri hasPrefix:@"File://"]) {
	fileUri = [fileUri substringFromIndex:7];
  }
  NSURL *url = [NSURL fileURLWithPath:fileUri];
  
  // 文件总大小
  int64_t totalFileSize = [self fileSizeAtPath:url.path create:NO];
  
  // 剩余文件大小
  int64_t restFileSize = totalFileSize - offset;
  
  // 文件分片大小
  int64_t sliceSize = 1*1024*1024;
  
  if (requestId) {
	//.cssg-snippet-body-start:[objc-upload-part]
	QCloudUploadPartRequest* request = [QCloudUploadPartRequest new];
	
	// 存储桶名称，格式为 BucketName-APPID
	request.bucket = bucket;
	
	// 对象键，是对象在 COS 上的完整路径，如果带目录的话，格式为 "dir1/object1"
	request.object = cosPath;
	
	// 块编号
	request.partNumber = partNumber;
	
	// 标识本次分块上传的 ID；使用 Initiate Multipart Upload 接口初始化分块上传时会得到一个 uploadId
	request.uploadId = requestId;
	
	// 如果剩余上传大小小于分片大小则用剩余的大小进行切片
	int64_t slice = restFileSize >= sliceSize ? sliceSize : restFileSize;
	QCloudFileOffsetBody *body = [[QCloudFileOffsetBody alloc] initWithFile:url offset:offset slice: slice];
	
	// 根据文件大小判断是否是最后一段分片
	BOOL last = slice + offset >= totalFileSize;
	
	// 上传的数据：支持 NSData*，NSURL(本地 URL) 和 QCloudFileOffsetBody * 三种类型
	request.body = body;
	
	[request setFinishBlock:^(QCloudUploadPartResult* outputObject, NSError *error) {
	  if (error) {
		reject([@(error.code) stringValue], error.localizedDescription, error);
	  } else {
		NSMutableDictionary* dic = [NSMutableDictionary new];
		[dic setObject:[NSNumber numberWithInt:partNumber] forKey:@"partNumber"];
		[dic setObject:outputObject.eTag forKey:@"eTag"];
		[dic setObject:[NSNumber numberWithLongLong:slice] forKey:@"partSize"];
		[dic setObject:[NSNumber numberWithLongLong:totalFileSize] forKey:@"fileSize"];
		[dic setObject:@(last) forKey:@"last"];
		resolve([dic copy]);
	  }
	}];
	
	[[QCloudCOSXMLService defaultCOSXML]  UploadPart:request];
  }
}

RCT_EXPORT_METHOD(completeUpload:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSString *bucket = [options objectForKey:@"bucket"];
  NSString *cosPath = [options objectForKey:@"cosPath"];
  NSString *requestId = [options objectForKey:@"requestId"];
  NSArray *uploadedParts = [options objectForKey:@"uploadedParts"];
  
  QCloudCompleteMultipartUploadRequest *completeRequst = [QCloudCompleteMultipartUploadRequest new];
  
  // 对象键，是对象在 COS 上的完整路径，如果带目录的话，格式为 "dir1/object1"
  completeRequst.object = cosPath;
  
  // 存储桶名称，格式为 BucketName-APPID
  completeRequst.bucket = bucket;
  
  // 本次要查询的分块上传的 uploadId，可从初始化分块上传的请求结果 QCloudInitiateMultipartUploadResult 中得到
  completeRequst.uploadId = requestId;
  
  // 已上传分块的信息
  QCloudCompleteMultipartUploadInfo *partInfo = [QCloudCompleteMultipartUploadInfo new];
  NSMutableArray *parts = [NSMutableArray array];
  for(int i =0; i < uploadedParts.count; i ++) {
	QCloudMultipartInfo *part = [QCloudMultipartInfo new];
	// 获取所上传分块的 etag
	part.eTag = [uploadedParts[i] objectForKey:@"eTag"];
	part.partNumber = [uploadedParts[i] objectForKey:@"partNumber"];
	
	[parts addObject:part];
  }
	  
  // 对已上传的块进行排序
  [parts sortUsingComparator:^NSComparisonResult(QCloudMultipartInfo*  _Nonnull obj1,
												 QCloudMultipartInfo*  _Nonnull obj2) {
	  int a = obj1.partNumber.intValue;
	  int b = obj2.partNumber.intValue;
	  
	  if (a < b) {
		  return NSOrderedAscending;
	  } else {
		  return NSOrderedDescending;
	  }
  }];
  partInfo.parts = [parts copy];
  completeRequst.parts = partInfo;
  
  [completeRequst setFinishBlock:^(QCloudUploadObjectResult * _Nonnull result,
								   NSError * _Nonnull error) {
	// 从 result 中获取上传结果
	NSMutableDictionary* dic = [NSMutableDictionary new];
	[dic setObject:[NSNumber numberWithLongLong:result.size] forKey:@"size"];
	[dic setObject:result.eTag forKey:@"eTag"];
	resolve([dic copy]);
  }];
  
  [[QCloudCOSXMLService defaultCOSXML] CompleteMultipartUpload:completeRequst];
}

RCT_EXPORT_METHOD(cancelUpload:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSString *bucket = [options objectForKey:@"bucket"];
  NSString *cosPath = [options objectForKey:@"cosPath"];
  NSString *requestId = [options objectForKey:@"requestId"];
  
  QCloudAbortMultipfartUploadRequest *abortRequest = [QCloudAbortMultipfartUploadRequest new];
  // 对象键，是对象在 COS 上的完整路径，如果带目录的话，格式为 "video/xxx/movie.mp4"
  abortRequest.object = cosPath;
  // 存储桶名称，由BucketName-Appid 组成，可以在COS控制台查看 https://console.cloud.tencent.com/cos5/bucket
  abortRequest.bucket = bucket;
  // 本次要终止的分块上传的 uploadId
  // 可从初始化分块上传的请求结果 QCloudInitiateMultipartUploadResult 中得到
  abortRequest.uploadId = requestId;
  [abortRequest setFinishBlock:^(id outputObject, NSError *error) {
	if (error) {
	  reject([@(error.code) stringValue], error.localizedDescription, error);
	} else {
	  resolve(nil);
	}
  }];
  
  [[QCloudCOSXMLService defaultCOSXML]AbortMultipfartUpload:abortRequest];
}

RCT_EXPORT_METHOD(download:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  NSString *bucket = [options objectForKey:@"bucket"];
  NSString *cosPath = [options objectForKey:@"cosPath"];
  NSString *requestId = [options objectForKey:@"requestId"];
  NSString* filePath = [options objectForKey:@"filePath"];
  
  int64_t offset = [self fileSizeAtPath:filePath create:YES];
  
  QCloudCOSXMLDownloadObjectRequest* request = [QCloudCOSXMLDownloadObjectRequest new];
  
  request.resumableDownload = YES;
  request.enableQuic = YES;
  request.bucket = bucket;
  request.object = cosPath;
  request.localCacheDownloadOffset = offset >= 1 ? offset - 1 : offset;

  NSURL *fileUrl = [NSURL fileURLWithPath:filePath];
  
  request.downloadingURL = fileUrl;

  [request setFinishBlock:^(id outputObject, NSError *error) {
	BOOL success = error == nil;
	NSDictionary* info = @{@"requestId": requestId,
						   @"success": @(success),
						   @"eTag": success ? [outputObject objectForKey:@"Etag"] : @"",
						 };
	dispatch_async(dispatch_get_main_queue(), ^{
	  [self sendMessageToRN:info toChannel:DOWNLOAD_RESULT_EVENT];
	});
  }];
  
  [request setDownProcessBlock:^(int64_t bytesDownload, int64_t totalBytesDownload, int64_t totalBytesExpectedToDownload) {
	NSDictionary* info = @{@"requestId": requestId,
						   @"processedBytes": totalBytesDownload < offset ? [NSNumber numberWithLongLong: offset] : [NSNumber numberWithLongLong: totalBytesDownload],
						   @"targetBytes": [NSNumber numberWithLongLong: totalBytesExpectedToDownload]
						   };
	dispatch_async(dispatch_get_main_queue(), ^{
	  [self sendMessageToRN:info toChannel:PROGRESS_EVENT];
	});
  }];
  
  [downloadTasks setObject:request forKey:requestId];
  
  [[QCloudCOSTransferMangerService defaultCOSTransferManager] DownloadObject:request];

  resolve(nil);
}


RCT_EXPORT_METHOD(pauseDownload:(NSString *)requestId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  if ([downloadTasks objectForKey:requestId]) {
	QCloudCOSXMLDownloadObjectRequest* request = [downloadTasks objectForKey:requestId];
	[request cancel];
  }
  
  resolve(nil);
}

RCT_EXPORT_METHOD(cancelDownload:(NSString *)requestId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  if ([downloadTasks objectForKey:requestId]) {
	QCloudCOSXMLDownloadObjectRequest* request = [downloadTasks objectForKey:requestId];
	[request cancel];
  }
  
  resolve(nil);
}

- (void) initService:(NSDictionary*)config {
  QCloudServiceConfiguration* configuration = [[QCloudServiceConfiguration alloc] init];
  configuration.signatureProvider = self;

  QCloudCOSXMLEndPoint* endpoint = [[QCloudCOSXMLEndPoint alloc] init];
  endpoint.regionName = [RCTConvert NSString:[config objectForKey:@"region"]];
  endpoint.useHTTPS = YES;
  configuration.endpoint = endpoint;
  [QCloudCOSXMLService registerDefaultCOSXMLWithConfiguration:configuration];
  [QCloudCOSTransferMangerService registerDefaultCOSTransferMangerWithConfiguration:configuration];

  self.credentialFenceQueue = [QCloudCredentailFenceQueue new];
  self.credentialFenceQueue.delegate = self;
  
  downloadTasks = [NSMutableDictionary new];
}

-(void)sendMessageToRN:(NSDictionary*)info toChannel:(NSString*)channel {
  [self sendEventWithName:channel body:[info copy]];
}

- (void)fenceQueue:(QCloudCredentailFenceQueue *)queue requestCreatorWithContinue:(QCloudCredentailFenceQueueContinue)continueBlock {
  g = dispatch_group_create();
  dispatch_group_enter(g);

  dispatch_group_notify(g, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
	if (self->sessionCredential && [self->sessionCredential.expirationDate compare:NSDate.date] == NSOrderedDescending) {
	  QCloudAuthentationV5Creator* creator = [[QCloudAuthentationV5Creator alloc] initWithCredential:self->sessionCredential];
	  continueBlock(creator, nil);
	} else {
	  continueBlock(nil, [NSError errorWithDomain:NSURLErrorDomain code:-1111 userInfo:@{NSLocalizedDescriptionKey:@"没有获取到临时密钥"}]);
	}
	self->g = nil;
  });
}

- (void) signatureWithFields:(QCloudSignatureFields*)fileds
					 request:(QCloudBizHTTPRequest*)request
				  urlRequest:(NSMutableURLRequest*)urlRequst
				   compelete:(QCloudHTTPAuthentationContinueBlock)continueBlock {
  if (secretKey && secretId) {
	// 使用永久秘钥
	QCloudCredential* credential = [QCloudCredential new];
	credential.secretID = secretId;
	credential.secretKey = secretKey;

	QCloudAuthentationV5Creator* creator = [[QCloudAuthentationV5Creator alloc] initWithCredential:credential];
	QCloudSignature* signature =  [creator signatureForData:urlRequst];
	continueBlock(signature, nil);
  } else {
  // 调用回调获取秘钥
	[self.credentialFenceQueue performAction:^(QCloudAuthentationCreator *creator, NSError *error) {
	  if (error) {
		  continueBlock(nil, error);
	  } else {
		  QCloudSignature* signature =  [creator signatureForData:urlRequst];
		  continueBlock(signature, nil);
	  }
	}];
  }
}

- (NSDictionary *)constantsToExport {
  return @{
   @"MainBundlePath": [[NSBundle mainBundle] bundlePath],
   @"CachesDirectoryPath": [self getPathForDirectory:NSCachesDirectory],
   @"DocumentDirectoryPath": [self getPathForDirectory:NSDocumentDirectory],
   @"ExternalDirectoryPath": [NSNull null],
   @"ExternalStorageDirectoryPath": [NSNull null],
   @"TemporaryDirectoryPath": NSTemporaryDirectory(),
   @"LibraryDirectoryPath": [self getPathForDirectory:NSLibraryDirectory],
   @"FileTypeRegular": NSFileTypeRegular,
   @"FileTypeDirectory": NSFileTypeDirectory,
   @"FileProtectionComplete": NSFileProtectionComplete,
   @"FileProtectionCompleteUnlessOpen": NSFileProtectionCompleteUnlessOpen,
   @"FileProtectionCompleteUntilFirstUserAuthentication": NSFileProtectionCompleteUntilFirstUserAuthentication,
   @"FileProtectionNone": NSFileProtectionNone
  };
}

- (NSString*) getParentPath:(NSString*) path {
  NSRange range = [path rangeOfString:@"/" options:NSBackwardsSearch];
  if (range.location != NSNotFound) {
	NSString *dir = [path substringToIndex: range.location];
	return dir;
  } else {
	return path;
  }
}

- (NSInteger) fileSizeAtPath:(NSString*) filePath
					  create:(BOOL) create{
  NSFileManager* manager = [NSFileManager defaultManager];
  
  if ([manager fileExistsAtPath:filePath]){
	NSDictionary * fileAttributes = [manager attributesOfItemAtPath:filePath error:nil];
	return [fileAttributes[NSFileSize] integerValue];
  } else {
	if (create) {
	  NSString *dir = [self getParentPath:filePath];
	  if (![manager fileExistsAtPath:dir]) {
		[manager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	  }
	  
	  if (![manager fileExistsAtPath:filePath]) {
		[manager createFileAtPath:filePath contents:nil attributes:nil];
	  }
	}
	return 0;
  }
}

- (NSString *)getPathForDirectory:(int)directory{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
  
  return [paths firstObject];
}

/// 获取文件的 mime type
- (NSString *)getMimeType:(NSString *) path{
	NSURL *url = [NSURL fileURLWithPath:path];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	NSHTTPURLResponse *response = nil;
	[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
	return response.MIMEType;
}

@end

