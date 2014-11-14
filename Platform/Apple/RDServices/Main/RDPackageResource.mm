//
//  RDPackageResource.mm
//  RDServices
//
//  Created by Shane Meyer on 2/28/13.
//  Copyright (c) 2014 Readium Foundation and/or its licensees. All rights reserved.
//  
//  Redistribution and use in source and binary forms, with or without modification, 
//  are permitted provided that the following conditions are met:
//  1. Redistributions of source code must retain the above copyright notice, this 
//  list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice, 
//  this list of conditions and the following disclaimer in the documentation and/or 
//  other materials provided with the distribution.
//  3. Neither the name of the organization nor the names of its contributors may be 
//  used to endorse or promote products derived from this software without specific 
//  prior written permission.
//  
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
//  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
//  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
//  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
//  OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED 
//  OF THE POSSIBILITY OF SUCH DAMAGE.

#import "RDPackageResource.h"
#import <ePub3/archive.h>
#import <ePub3/filter.h>
#import <ePub3/filter_chain.h>
#import <ePub3/filter_chain_byte_stream_range.h>
#import <ePub3/filter_chain_byte_stream.h>
#import <ePub3/package.h>
#import <ePub3/utilities/byte_stream.h>
#import "RDPackage.h"


@interface RDPackageResource() {
	@private UInt8 m_buffer[4096];
    @private std::unique_ptr<ePub3::ByteStream> m_byteStream;
	@private NSUInteger m_contentLength;
	@private UInt64 m_offset;
	@private NSData *m_data;
	@private __weak id <RDPackageResourceDelegate> m_delegate;
	@private RDPackage *m_package;
	@private NSString *m_relativePath;
    @private BOOL m_isRangeRequest;
    @private BOOL m_hasProperStream;
}

@end


@implementation RDPackageResource


@synthesize contentLength = m_contentLength;
@synthesize package = m_package;
@synthesize relativePath = m_relativePath;
@synthesize isRangeRequest = m_isRangeRequest;

- (void *)byteStream {
    return m_byteStream.get();
}


- (NSData *)data {
	if (m_data == nil) {
		NSMutableData *md = [[NSMutableData alloc] initWithCapacity:m_contentLength == 0 ? 1 : m_contentLength];
        
        if (!m_hasProperStream)
        {
            ePub3::ByteStream *byteStream = m_byteStream.release();
            m_byteStream.reset((ePub3::ByteStream *)[m_package getProperByteStream:m_relativePath currentByteStream:byteStream isRangeRequest:m_isRangeRequest]);
            m_hasProperStream = YES;
        }
        
        while (YES)
        {
            std::size_t count = m_byteStream->ReadBytes(m_buffer, sizeof(m_buffer));
            if (count <= 0)
            {
                break;
            }
            
            [md appendBytes:m_buffer length:count];
        }
        
		m_data = md;
	}

	return m_data;
}


- (void)dealloc {
}


- (instancetype)
	initWithDelegate:(id <RDPackageResourceDelegate>)delegate
	byteStream:(void *)byteStream
	package:(RDPackage *)package
	relativePath:(NSString *)relativePath
{
	if (byteStream == nil || package == nil || relativePath == nil || relativePath.length == 0) {
		return nil;
	}

	if (self = [super init]) {
        m_byteStream.reset((ePub3::ByteStream *)byteStream);
		m_contentLength = m_byteStream->BytesAvailable();
		m_delegate = delegate;
		m_package = package;
		m_relativePath = relativePath;
        m_isRangeRequest = NO;
        m_hasProperStream = NO;

		if (m_contentLength == 0) {
			NSLog(@"The resource content length is zero! %@", m_relativePath);
		}
	}

	return self;
}


- (NSData *)readDataOfLength:(NSUInteger)length {
	NSMutableData *md = [[NSMutableData alloc] initWithCapacity:length];
    
    if (!m_hasProperStream)
    {
        ePub3::ByteStream *byteStream = m_byteStream.release();
        m_byteStream.reset((ePub3::ByteStream *)[m_package getProperByteStream:m_relativePath currentByteStream:byteStream isRangeRequest:m_isRangeRequest]);
        m_hasProperStream = YES;
    }
    
    if (!m_isRangeRequest)
    {
        [md appendBytes:[self data].bytes length:length];
        return md;
    }

	ePub3::FilterChainByteStreamRange *filterStream =
		dynamic_cast<ePub3::FilterChainByteStreamRange *>(m_byteStream.get());

	if (filterStream == nullptr) {
		NSLog(@"The byte stream is not a FilterChainSyncStream!");
	}
	else {
		ePub3::ByteRange range;
		range.Location(m_offset);
		NSUInteger totalRead = 0;

		while (totalRead < length) {
			range.Length(MIN(sizeof(m_buffer), length - totalRead));
			std::size_t count = filterStream->ReadBytes(m_buffer, sizeof(m_buffer), range);
			[md appendBytes:m_buffer length:count];
			totalRead += count;
            m_offset += count;
            range.Location(range.Location() + count);

			if (count != range.Length()) {

                //TODO: this seems to happen quite often? Is this expected?
				NSLog(@"Did not read the expected number of bytes! (%lu %lu)",
					count, (unsigned long)range.Length());
				break;
			}
		}
	}

	return md;
}


- (void)setOffset:(UInt64)offset {
	m_offset = offset;
}

@end
