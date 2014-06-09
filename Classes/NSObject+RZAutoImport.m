//
//  NSObject+RZAutoImport.m
//  RZAutoImport
//
//  Created by Nick Donaldson on 5/21/14.
//
//  Copyright 2014 Raizlabs and other contributors
//  http://raizlabs.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "NSObject+RZAutoImport.h"
#import "NSObject+RZAutoImport_Private.h"
#import <objc/runtime.h>


static NSString* const kRZAutoImportISO8601DateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";

//
//  Private Utility Macros/Functions
//

#if ( DEBUG )
#define RZAILogDebug(msg, ...) NSLog((@"[RZAutoImport : DEBUG] " msg), ##__VA_ARGS__)
#else
#define RZAILogDebug(...)
#endif

#define RZAILogError(msg, ...) NSLog((@"[RZAutoImport : ERROR] " msg), ##__VA_ARGS__);

#define RZAINSNullToNil(x) ([x isEqual:[NSNull null]] ? nil : x)

static objc_property_t rzai_getProperty(NSString *name, Class class) {
    
    objc_property_t property = class_getProperty( class, [name UTF8String] );
    
    if ( property == NULL) {
        // check base classes
        Class baseClass = class_getSuperclass( class );
        while ( baseClass != Nil && property == NULL) {
            property  = class_getProperty( baseClass, [name UTF8String] );
            baseClass = class_getSuperclass( baseClass );
        }
    }
    
    return property;
}

static RZAutoImportDataType rzai_dataTypeForProperty(NSString *propertyName, Class aClass) {
    
    objc_property_t property = rzai_getProperty(propertyName, aClass);
    if ( property == nil ) {
        return RZAutoImportDataTypeUnknown;
    }
    
    char *typeEncoding = nil;
    typeEncoding = property_copyAttributeValue(property, "T");
    
    if ( typeEncoding == NULL ) {
        return RZAutoImportDataTypeUnknown;
    }
    
    RZAutoImportDataType type = RZAutoImportDataTypeUnknown;
    
    switch ( typeEncoding[0] ) {
            
            // Object class
        case '@': {
            
            NSUInteger typeLength = (NSUInteger)strlen(typeEncoding);
            
            if ( typeLength > 3 ) {
                NSString *typeString = [[NSString stringWithUTF8String:typeEncoding] substringWithRange:NSMakeRange(2, typeLength - 3)];
                type = rzai_dataTypeFromString(typeString);
            }
        }
            break;
            
            // Primitive type
        case 'c':
        case 'C':
        case 'i':
        case 'I':
        case 's':
        case 'S':
        case 'l':
        case 'L':
        case 'q':
        case 'Q':
        case 'f':
        case 'd':
        case 'B':
            type = RZAutoImportDataTypePrimitive;
            break;
            
        default:
            break;
    }
    
    if ( typeEncoding ) {
        free(typeEncoding), typeEncoding = NULL;
    }
    
    return type;
}

static NSArray* rzai_propertyNamesForClass(Class aClass) {
    
    unsigned int    count;
    objc_property_t *properties = class_copyPropertyList( aClass, &count );
    
    NSMutableArray *names = [NSMutableArray array];
    
    for ( unsigned int i = 0; i < count; i++ ) {
        objc_property_t property      = properties[i];
        NSString        *propertyName = [NSString stringWithUTF8String:property_getName( property )];
        if ( propertyName ) {
            [names addObject:propertyName];
        }
    }
    
    if ( properties ) {
        free( properties ), properties = NULL;
    }
    
    return names;
}

static SEL rzai_setterForProperty(Class aClass, NSString *propertyName) {
    
    NSString        *setterString = nil;
    objc_property_t property      = rzai_getProperty(propertyName, aClass);
    if ( property ) {
        char *setterCString = property_copyAttributeValue( property, "S" );
        
        if ( setterCString ) {
            setterString = [NSString stringWithUTF8String:setterCString];
            free( setterCString );
        }
        else {
            setterString = [NSString stringWithFormat:@"set%@:", [propertyName stringByReplacingCharactersInRange:NSMakeRange( 0, 1 ) withString:[[propertyName substringToIndex:1] capitalizedString]]];
        }
    }
    
    return setterString ? NSSelectorFromString( setterString ) : nil;
}

//
//  Private Header Implementations

NSString *rzai_normalizedKey(NSString *key) {
    if ( key == nil ) {
        return nil;
    }
    return [[key lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@""];
}

RZAutoImportDataType rzai_dataTypeFromString(NSString *string)
{
    Class objClass = NSClassFromString(string);
    if ( objClass == Nil ){
        return RZAutoImportDataTypeUnknown;
    }
    
    RZAutoImportDataType type = RZAutoImportDataTypeOtherObject;
    
    if ( [objClass isSubclassOfClass:[NSString class]] ){
        type = RZAutoImportDataTypeNSString;
    }
    else if ( [objClass isSubclassOfClass:[NSNumber class]] ){
        type = RZAutoImportDataTypeNSNumber;
    }
    else if ( [objClass isSubclassOfClass:[NSDate class]] ){
        type = RZAutoImportDataTypeNSDate;
    }
    else if ( [objClass isSubclassOfClass:[NSArray class]] ){
        type = RZAutoImportDataTypeNSArray;
    }
    else if ( [objClass isSubclassOfClass:[NSDictionary class]] ){
        type = RZAutoImportDataTypeNSDictionary;
    }
    else if ( [objClass isSubclassOfClass:[NSSet class]] ) {
        type = RZAutoImportDataTypeNSSet;
    }
    
    return type;
}


@implementation RZAIPropertyInfo

// Implementation is empty on purpose - just a simple POD class.

@end

//
//  Category Implementation
//

@implementation NSObject (RZAutoImport)

#pragma mark - Static

+ (NSMutableDictionary *)s_rzai_importMappingCache
{
    static NSMutableDictionary *s_importMappingCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_importMappingCache = [NSMutableDictionary dictionary];
    });
    return s_importMappingCache;
}

+ (NSSet *)s_rzai_ignoredClasses
{
    static NSSet *s_ignoredClasses = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_ignoredClasses = [NSSet setWithArray:@[
                                                 @"NSObject",
                                                 @"NSManagedObject"
                                                 ]];
    });
    return s_ignoredClasses;
}

+ (NSNumberFormatter *)s_rzai_numberFormatter
{
    static NSNumberFormatter *s_numberFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_numberFormatter = [[NSNumberFormatter alloc] init];
        s_numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        
        // !!!: The locale is mandated to be US, so JSON API responses will parse correctly regardless of locality.
        //      If other localization is required, custom import blocks must be used.
        s_numberFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return s_numberFormatter;
}

+ (NSDateFormatter *)s_rzai_dateFormatter
{
    static NSDateFormatter *s_dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_dateFormatter = [[NSDateFormatter alloc] init];
        s_dateFormatter.dateFormat = kRZAutoImportISO8601DateFormat;
        
        // !!!: The time zone is mandated to be GMT for parsing string dates.
        //      Any timezone offsets should be encoded into the date string or handled on the display level.
        s_dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        
        // !!!: The locale is mandated to be US, so JSON API responses will parse correctly regardless of locality.
        //      If other localization is required, custom import blocks must be used.
        s_dateFormatter.locale   = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return s_dateFormatter;
}

/**
 *  Recursive mutex lock used for resource contention.
 *  Custom import blocks may call into this category so the lock
 *  must be recursive in order to support recursive accesses on
 *  the same thread within the same stack frame.
 */
+ (NSRecursiveLock *)s_rzai_mutex
{
    static NSRecursiveLock *s_mutex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_mutex = [[NSRecursiveLock alloc] init];
    });
    return s_mutex;
}

#pragma mark - Public

+ (instancetype)rzai_objectFromDictionary:(NSDictionary *)dict
{
    NSParameterAssert(dict);
    
    id object = nil;
    
    if ( [self respondsToSelector:@selector( rzai_existingObjectForDict: )] ) {
        Class <RZAutoImportable> thisClass = [self class];
        object = [thisClass rzai_existingObjectForDict:dict];
    }
    
    if ( object == nil ) {
        object = [[self alloc] init];
    }
    
    [object rzai_importValuesFromDict:dict];
    
    return object;
}

+ (NSArray *)rzai_objectsFromArray:(NSArray *)array
{
    NSParameterAssert(array);
    
    NSMutableArray *objects = [NSMutableArray array];
    [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSAssert([obj isKindOfClass:[NSDictionary class]], @"Array passed to rzai_objectsFromArray: must only contain NSDictionary instances");
        if ( [obj isKindOfClass:[NSDictionary class]] ) {
            id importedObj = [self rzai_objectFromDictionary:obj];
            if ( importedObj ) {
                [objects addObject:importedObj];
            }
        }
    }];
    
    return [NSArray arrayWithArray:objects];
}

- (void)rzai_importValuesFromDict:(NSDictionary *)dict
{
    BOOL canOverrideImports = [self respondsToSelector:@selector( rzai_shouldImportValue:forKey: )];
    
    NSDictionary *importMapping = [[self class] rzai_importMapping];
    
    [dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        
        if ( canOverrideImports ) {
            if ( ![(id<RZAutoImportable>)self rzai_shouldImportValue:value forKey:key] ) {
                return;
            }
        }
        
        RZAIPropertyInfo *propDescriptor = [importMapping objectForKey:rzai_normalizedKey(key)];
        value = RZAINSNullToNil(value);
        
        if ( propDescriptor ) {
            [self rzai_setValue:value fromKey:key forPropertyDescriptor:propDescriptor];
        }
        else {
            RZAILogDebug(@"No property found in class %@ for key %@. Create a custom mapping to import a value for this key.", NSStringFromClass([self class]), key);
        }
    }];
}


+ (NSDictionary *)rzai_importMapping
{
    __block NSDictionary *returnMapping = nil;
    
    [self rzai_performBlockAtomically:^{
        
        NSString            *className = NSStringFromClass( self );
        NSMutableDictionary *mapping   = [[[self class] s_rzai_importMappingCache] objectForKey:className];
        
        if ( mapping == nil ) {
            
            mapping = [NSMutableDictionary dictionary];
            
            // Get mappings from the normalized property names
            [mapping addEntriesFromDictionary:[self rzai_normalizedPropertyMappings]];
            
            // Get any mappings from the RZAutoImportable protocol
            if ( [[self class] respondsToSelector:@selector( rzai_customMappings )] ) {
                
                Class <RZAutoImportable> thisClass = [self class];
                NSDictionary *customMappings = [thisClass rzai_customMappings];
                
                [customMappings enumerateKeysAndObjectsUsingBlock:^( NSString *keyname, NSString *propName, BOOL *stop ) {
                    RZAIPropertyInfo *propDescriptor = [[RZAIPropertyInfo alloc] init];
                    propDescriptor.propertyName = propName;
                    propDescriptor.dataType = rzai_dataTypeForProperty(propName, self);
                    [mapping setObject:propDescriptor forKey:rzai_normalizedKey(keyname)];
                }];
            }
            
            [[[self class] s_rzai_importMappingCache] setObject:mapping forKey:className];
        }
        
        returnMapping = [NSDictionary dictionaryWithDictionary:mapping];
    }];
    
    return returnMapping;
}

#pragma mark - Private

+ (void)rzai_performBlockAtomically:(void(^)())block
{
    [[self s_rzai_mutex] lock];
    if ( block ) {
        block();
    }
    [[self s_rzai_mutex] unlock];
}

+ (NSDictionary *)rzai_normalizedPropertyMappings
{
    NSMutableDictionary *mappings = [NSMutableDictionary dictionary];
    
    // Get property names from this class and all inherited classes
    NSMutableArray *propDescriptors = [NSMutableArray array];
    
    Class currentClass = [self class];
    while ( currentClass != Nil ) {
        
        NSString *className = NSStringFromClass(currentClass);
        
        if ( ![[[self class] s_rzai_ignoredClasses] containsObject:className] ) {
            NSArray *classPropNames = rzai_propertyNamesForClass(currentClass);
            [classPropNames enumerateObjectsUsingBlock:^(NSString *classPropName, NSUInteger idx, BOOL *stop) {
                RZAIPropertyInfo *propDescriptor = [[RZAIPropertyInfo alloc] init];
                propDescriptor.propertyName = classPropName;
                propDescriptor.dataType = rzai_dataTypeForProperty(classPropName, self);
                [propDescriptors addObject:propDescriptor];
            }];
        }
        
        currentClass = class_getSuperclass( currentClass );
    }
    
    [propDescriptors enumerateObjectsUsingBlock:^(RZAIPropertyInfo *propDescriptor, NSUInteger idx, BOOL *stop) {
        [mappings setObject:propDescriptor forKey:rzai_normalizedKey(propDescriptor.propertyName)];
    }];
    
    return [NSDictionary dictionaryWithDictionary:mappings];
}

- (void)rzai_setNilForPropertyNamed:(NSString *)propName
{
    SEL setter = rzai_setterForProperty([self class], propName);
    if ( setter == nil ) {
        RZAILogError(@"Setter not available for property named %@", propName);
        return;
    }
    
    NSMethodSignature *methodSig  = [self methodSignatureForSelector:setter];
    NSInvocation      *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
    
    [invocation setTarget:self];
    [invocation setSelector:setter];
    
    // The buffer is copied so this is OK even though it will go out of scope
    id nilValue = nil;
    [invocation setArgument:&nilValue atIndex:2];
    [invocation invoke];
}

- (void)rzai_setValue:(id)value fromKey:(NSString *)originalKey forPropertyDescriptor:(RZAIPropertyInfo *)propDescriptor
{
    @try {
        if ( value == nil ) {
            [self rzai_setNilForPropertyNamed:propDescriptor.propertyName];
        }
        else {
            
            id convertedValue = nil;
            
            if ( [value isKindOfClass:[NSNumber class]] ) {
                
                switch (propDescriptor.dataType) {
                        
                    case RZAutoImportDataTypeNSNumber:
                    case RZAutoImportDataTypePrimitive:
                        convertedValue = value;
                        break;
                        
                    case RZAutoImportDataTypeNSString:
                        convertedValue = [value stringValue];
                        break;
                        
                    case RZAutoImportDataTypeNSDate: {
                        // Assume it's a unix timestamp
                        convertedValue = [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
                        
                        RZAILogDebug(@"Received a number for key [%@] matching property [%@] of class [%@]. Assuming unix timestamp.",
                                     originalKey,
                                     propDescriptor.propertyName,
                                     NSStringFromClass([self class]));
                    }
                        break;
                        
                    default:
                        break;
                }
                
            }
            else if ( [value isKindOfClass:[NSString class]] ) {
                
                switch (propDescriptor.dataType) {
                        
                    case RZAutoImportDataTypePrimitive:
                    case RZAutoImportDataTypeNSNumber: {
                        __block NSNumber *number = nil;
                        [[self class] rzai_performBlockAtomically:^{
                            number = [[[self class] s_rzai_numberFormatter] numberFromString:value];
                        }];
                        convertedValue = number;
                    }
                        break;
                        
                    case RZAutoImportDataTypeNSString:
                        convertedValue = value;
                        break;
                        
                    case RZAutoImportDataTypeNSDate: {
                        // Check for a date format from the object. If not provided, use ISO-8601.
                        __block NSDate *date = nil;
                        [[self class] rzai_performBlockAtomically:^{
                            
                            NSString        *dateFormat     = nil;
                            NSDateFormatter *dateFormatter  = [[self class] s_rzai_dateFormatter];
                            
                            if ( [[self class] respondsToSelector:@selector(rzai_dateFormatForKey:)] ) {
                                Class <RZAutoImportable> thisClass = [self class];
                                dateFormat = [thisClass rzai_dateFormatForKey:originalKey];
                            }
                            
                            if ( dateFormat == nil ) {
                                dateFormat = kRZAutoImportISO8601DateFormat;
                            }
                            
                            dateFormatter.dateFormat = dateFormat;
                            date = [dateFormatter dateFromString:value];
                        }];
                        convertedValue = date;
                        
                    }
                        break;
                        
                    default:
                        break;
                }
                
            }
            else if ( [value isKindOfClass:[NSDate class]] ) {
                
                // This will not occur in raw JSON deserialization,
                // but the conversion may have already happened in an external method.
                if ( propDescriptor.dataType == RZAutoImportDataTypeNSDate ) {
                    convertedValue = value;
                }
            }
            
            if ( convertedValue ) {
                [self setValue:convertedValue forKey:propDescriptor.propertyName];
            }
            else {
                RZAILogError(@"Could not convert value of type [%@] from key [%@] to correct type for property [%@] of class [%@]",
                             NSStringFromClass([value class]),
                             originalKey,
                             propDescriptor.propertyName,
                             NSStringFromClass([self class]));
            }
        }
    }
    @catch ( NSException *exception ) {
        RZAILogError(@"Could not set value %@ for property %@ of class %@", value, propDescriptor.propertyName, NSStringFromClass([self class]));
    }
}

@end
