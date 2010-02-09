/*****************************************************
*  
*  Copyright 2009 Adobe Systems Incorporated.  All Rights Reserved.
*  
*****************************************************
*  The contents of this file are subject to the Mozilla Public License
*  Version 1.1 (the "License"); you may not use this file except in
*  compliance with the License. You may obtain a copy of the License at
*  http://www.mozilla.org/MPL/
*   
*  Software distributed under the License is distributed on an "AS IS"
*  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
*  License for the specific language governing rights and limitations
*  under the License.
*   
*  
*  The Initial Developer of the Original Code is Adobe Systems Incorporated.
*  Portions created by Adobe Systems Incorporated are Copyright (C) 2009 Adobe Systems 
*  Incorporated. All Rights Reserved. 
*  
*****************************************************/
package org.osmf.elements
{
	import flash.events.Event;
	
	import flexunit.framework.TestCase;
	
	import org.osmf.events.SeekEvent;
	import org.osmf.media.MediaElement;
	import org.osmf.traits.MediaTraitType;
	import org.osmf.traits.SeekTrait;
	import org.osmf.traits.TimeTrait;
	import org.osmf.utils.DynamicMediaElement;
	import org.osmf.utils.DynamicSeekTrait;
	import org.osmf.utils.DynamicTimeTrait;
	
	public class TestParallelElementWithSeekTrait extends TestCase
	{
		override public function setUp():void
		{
			events = [];
		}
		
		public function testSeekTrait():void
		{
			var parallel:ParallelElement = new ParallelElement();

			// No trait to begin with.
			assertTrue(parallel.getTrait(MediaTraitType.TIME) == null);
			assertTrue(parallel.getTrait(MediaTraitType.SEEK) == null);

			// Adding a seekTrait with a duration-less timeTrait should prevent seeking.
			var mediaElement0:MediaElement = new DynamicMediaElement([MediaTraitType.TIME, MediaTraitType.SEEK], null, null, true);
			var seekTrait0:SeekTrait = mediaElement0.getTrait(MediaTraitType.SEEK) as SeekTrait;
			var timeTrait0:DynamicTimeTrait = mediaElement0.getTrait(MediaTraitType.TIME) as DynamicTimeTrait;
			parallel.addChild(mediaElement0);
			timeTrait0.duration = NaN;
			
			var seekTrait:SeekTrait = parallel.getTrait(MediaTraitType.SEEK) as SeekTrait;
			assertTrue(seekTrait.canSeekTo(0) == false);
			
			parallel.removeChild(mediaElement0);

			var mediaElement1:MediaElement = new DynamicMediaElement([MediaTraitType.TIME, MediaTraitType.SEEK], null, null, true);
			var timeTrait1:DynamicTimeTrait = mediaElement1.getTrait(MediaTraitType.TIME) as DynamicTimeTrait;
			var seekTrait1:DynamicSeekTrait = mediaElement1.getTrait(MediaTraitType.SEEK) as DynamicSeekTrait;

			var mediaElement2:MediaElement = new DynamicMediaElement([MediaTraitType.TIME, MediaTraitType.SEEK], null, null, true);
			var timeTrait2:DynamicTimeTrait = mediaElement2.getTrait(MediaTraitType.TIME) as DynamicTimeTrait;
			var seekTrait2:DynamicSeekTrait = mediaElement2.getTrait(MediaTraitType.SEEK) as DynamicSeekTrait;
			
			timeTrait1.duration = 20;
			timeTrait1.currentTime = 0;
			timeTrait2.duration = 40;
			timeTrait2.currentTime = 0;
			
			parallel.addChild(mediaElement1);
			parallel.addChild(mediaElement2);
			
			var timeTrait:TimeTrait = parallel.getTrait(MediaTraitType.TIME) as TimeTrait;
			seekTrait = parallel.getTrait(MediaTraitType.SEEK) as SeekTrait;
			assertTrue(timeTrait != null);
			assertTrue(seekTrait != null);
			assertTrue(seekTrait.seeking == false);
			
			seekTrait.addEventListener(SeekEvent.SEEK_BEGIN, eventCatcher);
			seekTrait.addEventListener(SeekEvent.SEEK_END, eventCatcher);
			
			assertTrue(seekTrait.canSeekTo(10) == true);
			assertTrue(seekTrait.canSeekTo(25) == true);
			assertTrue(seekTrait.canSeekTo(55) == false);
			assertTrue(seekTrait.canSeekTo(Number.NaN) == false);
			assertTrue(seekTrait.canSeekTo(-100) == false);
			
			var currentTime:Number = 18;
			seekTrait.seek(currentTime);
			seekTrait1.completeSeek(currentTime);
			seekTrait2.completeSeek(currentTime);
			assertTrue(events.length == 2);
			assertTrue(timeTrait1.currentTime == currentTime);
			assertTrue(timeTrait2.currentTime == currentTime);

			currentTime = 5;
			seekTrait.seek(currentTime);
			
			seekTrait.seek(10);
			assertTrue(timeTrait1.currentTime != 10);
			assertTrue(timeTrait2.currentTime != 10);
			
			seekTrait1.completeSeek(currentTime);
			seekTrait2.completeSeek(currentTime);
			assertTrue(events.length == 5);
			assertTrue(timeTrait1.currentTime == currentTime);
			assertTrue(timeTrait2.currentTime == currentTime);

			currentTime = 25;
			seekTrait.seek(currentTime);
			seekTrait1.completeSeek(timeTrait1.duration);
			seekTrait2.completeSeek(currentTime);
			assertTrue(events.length == 7);
			assertTrue(timeTrait1.currentTime == timeTrait1.duration);
			assertTrue(timeTrait2.currentTime == currentTime);
			
			var invalidCurrentTime:Number = -100;
			seekTrait.seek(invalidCurrentTime);
			assertTrue(timeTrait1.currentTime != invalidCurrentTime);
			assertTrue(timeTrait2.currentTime != invalidCurrentTime);

			invalidCurrentTime = Number.NaN;
			seekTrait.seek(invalidCurrentTime);
			assertTrue(timeTrait1.currentTime != invalidCurrentTime);
			assertTrue(timeTrait2.currentTime != invalidCurrentTime);

			invalidCurrentTime = 2000;
			seekTrait.seek(invalidCurrentTime);
			assertTrue(timeTrait1.currentTime != invalidCurrentTime);
			assertTrue(timeTrait2.currentTime != invalidCurrentTime);
			
		}
		
		public function testSeekTraitWithAddUnseekableChild():void
		{
			var parallel:ParallelElement = new ParallelElement();

			// No trait to begin with.
			assertTrue(parallel.getTrait(MediaTraitType.TIME) == null);
			assertTrue(parallel.getTrait(MediaTraitType.SEEK) == null);

			var mediaElement1:MediaElement = new DynamicMediaElement([MediaTraitType.TIME, MediaTraitType.SEEK], null, null, true);
			var timeTrait1:DynamicTimeTrait = mediaElement1.getTrait(MediaTraitType.TIME) as DynamicTimeTrait;
			var seekTrait1:DynamicSeekTrait = mediaElement1.getTrait(MediaTraitType.SEEK) as DynamicSeekTrait;

			var mediaElement2:MediaElement = new DynamicMediaElement([MediaTraitType.TIME], null, null, true);
			var timeTrait2:DynamicTimeTrait = mediaElement2.getTrait(MediaTraitType.TIME) as DynamicTimeTrait;

			var mediaElement3:MediaElement = new DynamicMediaElement([MediaTraitType.TIME, MediaTraitType.SEEK], null, null, true);
			var timeTrait3:DynamicTimeTrait = mediaElement3.getTrait(MediaTraitType.TIME) as DynamicTimeTrait;
			var seekTrait3:DynamicSeekTrait = mediaElement3.getTrait(MediaTraitType.SEEK) as DynamicSeekTrait;

			timeTrait1.duration = 20;
			timeTrait1.currentTime = 0;
			timeTrait2.duration = 40;
			timeTrait2.currentTime = 0;
			timeTrait3.duration = 10;
			timeTrait3.currentTime = 0;

			parallel.addChild(mediaElement1);
			parallel.addChild(mediaElement2);
			parallel.addChild(mediaElement3);

			var timeTrait:TimeTrait = parallel.getTrait(MediaTraitType.TIME) as TimeTrait;
			var seekTrait:SeekTrait = parallel.getTrait(MediaTraitType.SEEK) as SeekTrait;
			assertTrue(timeTrait != null);
			assertTrue(seekTrait != null);
			assertTrue(seekTrait.canSeekTo(10) == false);
		}
		
		private function eventCatcher(event:Event):void
		{
			events.push(event);
		}

		private var events:Array;
	}
}