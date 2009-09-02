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
package org.openvideoplayer.layout
{
	import flash.display.DisplayObject;
	import flash.errors.IllegalOperationError;
	import flash.events.Event;
	
	import org.openvideoplayer.metadata.Metadata;
	import org.openvideoplayer.metadata.MetadataNamespaces;
	import org.openvideoplayer.utils.MediaFrameworkStrings;

	/**
	 * Static utility functions used with Layouts.
	 */		
	public class LayoutUtils
	{
		// Public API
		//
		
		/**
		 * Function to postpone the execution of a method until the EXIT_FRAME event gets
		 * fired on the specified display object.
		 * 
		 * If this method is invoke multiple times before an EXIT_FRAME event occurs, then
		 * the system will queue them. Successive invokations will not add a new EXIT_FRAME
		 * listeners: all methods in the queue will be invoked as soon as the primary
		 * listener fires. The queue is executed first-in, first-out. 
		 *  
		 * @param displayObject The display object to listen on.
		 * @param method The method to invoke.
		 * @param arguments Optional array of arguments to pass to the method on invoking it.
		 */		
		public static function callLater(displayObject:DisplayObject, method:Function,arguments:Array=null):void
		{
			if (displayObject == null || method == null)
			{
				throw new IllegalOperationError(MediaFrameworkStrings.NULL_PARAM);
			}
			
			pendingCalls.push(method);
			pendingCallArguments.push(arguments || []);
			
			if	(	executingPendingCalls == false
				&&	dispatcher == null
				)
			{
				dispatcher = displayObject;
				dispatcher.addEventListener(Event.EXIT_FRAME, onExitFrame);
			}
		}
		
		/**
		 * Applies the specified absolute layout properties to a media element's metadata:
		 * 
		 * @param target Metadata that will get the specified properties set on its
		 * absolute layout facet.
		 * @param x
		 * @param y
		 * @param width
		 * @param height
		 * @return Either a newly created, or existing AbsoluteLayoutFacet instance that
		 * contains the specified properties.
		 * 
		 * Please referer to the AbsoluteLayoutFacet documentation for the semantics of
		 * the x, y, width, and height parameters.
		 */		
		public static function setAbsoluteLayout
								( target:Metadata
								, width:Number, height:Number
								, x:Number = NaN, y:Number = NaN
								):AbsoluteLayoutFacet
		{
			if (target == null)
			{
				throw new IllegalOperationError(MediaFrameworkStrings.NULL_PARAM);
			}
			
			var addFacet:Boolean;
			var absoluteLayout:AbsoluteLayoutFacet
				= 	target.getFacet(MetadataNamespaces.ABSOLUTE_LAYOUT_PARAMETERS)
					as AbsoluteLayoutFacet;
				
			if (absoluteLayout == null)
			{
				addFacet = true;
				absoluteLayout = new AbsoluteLayoutFacet();
			}
			
			if (!isNaN(x))
			{
				absoluteLayout.x = x;
			}
			
			if (!isNaN(y))
			{
				absoluteLayout.y = y;
			}
			
			if (!isNaN(width))
			{
				absoluteLayout.width = width;
			}
			
			if (!isNaN(height))
			{
				absoluteLayout.height = height;
			}
			
			if (addFacet)
			{
				target.addFacet(absoluteLayout);
			}
			
			return absoluteLayout;
		}
		
		// Internals
		//
		
		private static var dispatcher:DisplayObject;
		private static var executingPendingCalls:Boolean;
		private static var pendingCalls:Vector.<Function> = new Vector.<Function>;
		private static var pendingCallArguments:Vector.<Array> = new Vector.<Array>;
		
		private static function onExitFrame(event:Event):void
		{
			dispatcher.removeEventListener(Event.EXIT_FRAME, onExitFrame);
			dispatcher = null;
			
			executingPendingCalls = true;
			
			while (pendingCalls.length != 0)
			{
				var func:Function = pendingCalls.shift();
				var args:Array = pendingCallArguments.shift();
				
				func.apply(null,args);
			}
			
			executingPendingCalls = false;
		}
	}
}