/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Original - Christopher Lloyd <cjwl@objc.net>
#import <Foundation/NSCountedSet.h>
#import <Foundation/NSInlineSetTable.h>
#import <Foundation/NSEnumerator_set.h>
#import <Foundation/NSAutoreleasePool-private.h>

@implementation NSCountedSet : NSMutableSet

-initWithCapacity:(unsigned)capacity {
   _table=NSZoneMalloc([self zone],sizeof(NSSetTable));
   NSSetTableInit(_table,capacity,[self zone]);
   return self;
}

-(void)dealloc {
   NSSetTableFreeObjects(_table);
   NSSetTableFreeBuckets(_table);
   NSZoneFree(NSZoneFromPointer(_table),_table);
   NSDeallocateObject(self);
   return;
   [super dealloc];
}

-(unsigned)count {
   return ((NSSetTable *)_table)->count;
}

-member:object {
   return NSSetTableMember(_table,object);
}

-(NSEnumerator *)objectEnumerator {
   return NSAutorelease(NSEnumerator_setNew(NULL,self,_table));
}

-(void)addObject:object {
   NSSetTableAddObjectCount(_table,object);
}

-(void)removeObject:object {
   NSSetTableRemoveObjectCount(_table,object);
}

-(unsigned)countForObject:object {
   return NSSetTableObjectCount(_table,object);
}

@end
