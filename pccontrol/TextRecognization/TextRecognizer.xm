#include "TextRecognizer.h"
#import "VKOcrManager.h"
#import "../Screen.h"
#include "../Common.h"
#include "../AlertBox.h"

NSString* performTextRecognizerTextFromRawData(UInt8* eventData, NSError** error)
{
    if (SYSTEM_VERSION_LESS_THAN(@"13.0"))
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;OCR only supports iOS13 or newer version of iOS. iOS12 or older may be supported in the future.\r\n"}];
        showAlertBox(@"Not Supported", @"OCR only supports iOS13 or newer version of iOS. iOS12 and older may be supported in the future.", 99);
        return nil;
    }

    NSArray *data = [[NSString stringWithFormat:@"%s", eventData] componentsSeparatedByString:@";;"];
    if ([data count] == 0)
    {
        NSLog(@"com.zjx.springboard: Data not in good format.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Data not in good format.\r\n"}];
        return nil;
    }

    int task = [data[0] intValue];

    if (task == TASK_TEXT_FROM_AREA) // format: 1;;x1,y1,x2,y2;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path
    {
        if ([data count] < 8)
        {
            NSLog(@"com.zjx.springboard: Data not in good format. The format should be 1;;x1,,y1,,width,,height;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path.");
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Data not in good format. The format should be 1;;x1,,y1,,width,,height;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path\r\n"}];
            return nil;
        }

        VNRequestTextRecognitionLevel level = VNRequestTextRecognitionLevelAccurate;

        NSString* rectData = data[1]; // rect
        NSString* customWordsData = data[2];
        float minimumHeight = [data[3] floatValue];
        int levelData = [data[4] intValue];
        NSString* languagesData = data[5];
        BOOL correct = [data[6] boolValue];
        NSString* debugPath = data[7];

        // parse rect part
        NSArray *rect = [rectData componentsSeparatedByString:@",,"];
        if ([rect count] < 4)
        {
            NSLog(@"com.zjx.springboard: Rect data not in good format. The format should be x1,,y1,,width,,height");
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Rect data not in good format. The format should be x1,,y1,,width,,height\r\n"}];
            return nil;
        }
    
        CGRect recognizeRect = CGRectMake([rect[0] floatValue], [rect[1] floatValue], [rect[2] floatValue], [rect[3] floatValue]);
        // parse customwords part
        NSArray *customWords = [customWordsData componentsSeparatedByString:@",,"];

        // parse minimum_height part
        if (minimumHeight <= 0)
        {
            minimumHeight = 1/32;
        }

        // parse level
        if (levelData == 1)
        {
            level = VNRequestTextRecognitionLevelFast;
        }
        // parse languages part
        NSArray *languages = [languagesData componentsSeparatedByString:@",,"];

                // OCR 内部截图，由 finally 统一释放。
        CGImageRef screenshot = NULL;
        VKOcrManager *ocrManager = nil;

        @try
        {
            screenshot = [Screen createScreenShotCGImageRef];

            // 截图失败时，不再继续创建 OCR 对象。
            if (screenshot == NULL)
            {
                if (error != NULL)
                {
                    *error = [NSError
                        errorWithDomain:@"com.zjx.zxtouchsp"
                        code:999
                        userInfo:@{
                            NSLocalizedDescriptionKey:
                                @"-1;;Unable to capture screenshot for OCR\r\n"
                        }];
                }

                return nil;
            }

            int orientation = [Screen getScreenOrientation];

            ocrManager = [[VKOcrManager alloc]
                initWithCGImage:screenshot
                area:recognizeRect
                orientation:orientation];

            if (ocrManager == nil)
            {
                if (error != NULL)
                {
                    *error = [NSError
                        errorWithDomain:@"com.zjx.zxtouchsp"
                        code:999
                        userInfo:@{
                            NSLocalizedDescriptionKey:
                                @"-1;;Unable to create OCR manager\r\n"
                        }];
                }

                return nil;
            }

            // 保留原来的自定义词汇配置。
            if (customWords.count > 1 ||
                (customWords.count == 1 &&
                 ![customWords[0] isEqualToString:@""]))
            {
                [ocrManager setCustomWords:customWords];
            }

            [ocrManager setMinimumHeight:minimumHeight];
            [ocrManager setRecognitionLevel:level];

            // 保留原来的识别语言配置。
            if (languages.count > 1 ||
                (languages.count == 1 &&
                 ![languages[0] isEqualToString:@""]))
            {
                [ocrManager setLanguages:languages];
            }

            [ocrManager setCorrection:correct];

            // 执行 OCR。
            NSString *result = [ocrManager recognize:error];

            // 识别成功且设置了路径时，才输出调试图片。
            // 必须在释放 manager 之前执行。
            if (result != nil && debugPath.length > 0)
            {
                [ocrManager outputDebugImage:debugPath error:error];
            }

            return result;
        }
        @finally
        {
            // 已修复 completion block 循环引用，
            // manager 及其持有的对象由 ARC 清理。
            ocrManager = nil;

            // 释放本次创建的截图引用，只释放一次。
            if (screenshot != NULL)
            {
                CGImageRelease(screenshot);
                screenshot = NULL;
            }
        }
    }
    else if (task == TASK_GET_SUPPORTED_LANGUAGE_LIST)
    {
        if ([data count] < 2)
        {
            NSLog(@"com.zjx.springboard: Data not in good format. The format should be 2;;level data:%@", data);
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Data not in good format. The format should be 2;;level\r\n"}];
            return nil;
        }
        VNRequestTextRecognitionLevel level = VNRequestTextRecognitionLevelAccurate;

        int levelData = [data[1] intValue];
        if (levelData == 1)
        {
            level = VNRequestTextRecognitionLevelFast;
        }

        NSArray *supportedLanguage;
        if (SYSTEM_VERSION_LESS_THAN(@"14.0"))
        {
            supportedLanguage = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level revision:1 error:error];
        }
        else
        {
            supportedLanguage = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level revision:2 error:error];
        }

        return [supportedLanguage componentsJoinedByString:@";;"];
    }
    else 
    {
        NSLog(@"com.zjx.springboard: Text recognition unknown task type");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Text recognition unknown task type\r\n"}];
        return nil;
    }
}
