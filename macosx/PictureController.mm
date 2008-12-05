/* $Id: PictureController.mm,v 1.11 2005/08/01 15:10:44 titer Exp $

   This file is part of the HandBrake source code.
   Homepage: <http://handbrake.fr/>.
   It may be used under the terms of the GNU General Public License. */

#import "PictureController.h"

@interface PictureController (Private)

- (NSSize)optimalViewSizeForImageSize: (NSSize)imageSize;
- (void)resizeSheetForViewSize: (NSSize)viewSize;
- (void)setViewSize: (NSSize)viewSize;
- (BOOL)viewNeedsToResizeToSize: (NSSize)newSize;

@end

@implementation PictureController

- (id)initWithDelegate:(id)del
{
	if (self = [super initWithWindowNibName:@"PictureSettings"])
	{
        // NSWindowController likes to lazily load its window. However since
        // this controller tries to set all sorts of outlets before the window
        // is displayed, we need it to load immediately. The correct way to do
        // this, according to the documentation, is simply to invoke the window
        // getter once.
        //
        // If/when we switch a lot of this stuff to bindings, this can probably
        // go away.
        [self window];
        
		delegate = del;
        fPicturePreviews = [[NSMutableDictionary dictionaryWithCapacity: HB_NUM_HBLIB_PICTURES] retain];
        /* Init libhb with check for updates libhb style set to "0" so its ignored and lets sparkle take care of it */
        int loggingLevel = [[[NSUserDefaults standardUserDefaults] objectForKey:@"LoggingLevel"] intValue];
        fPreviewLibhb = hb_init(loggingLevel, 0);
	}
	return self;
}

- (void) dealloc
{
    hb_stop(fPreviewLibhb);
    if (fPreviewMoviePath)
    {
        [[NSFileManager defaultManager] removeFileAtPath:fPreviewMoviePath handler:nil];
        [fPreviewMoviePath release];
    }    
    
    [fLibhbTimer invalidate];
    [fLibhbTimer release];
    
    [fPicturePreviews release];
    [super dealloc];
}

- (void) SetHandle: (hb_handle_t *) handle
{
    fHandle = handle;
    
    [fWidthStepper  setValueWraps: NO];
    [fWidthStepper  setIncrement: 16];
    [fWidthStepper  setMinValue: 64];
    [fHeightStepper setValueWraps: NO];
    [fHeightStepper setIncrement: 16];
    [fHeightStepper setMinValue: 64];
    
    [fCropTopStepper    setIncrement: 2];
    [fCropTopStepper    setMinValue:  0];
    [fCropBottomStepper setIncrement: 2];
    [fCropBottomStepper setMinValue:  0];
    [fCropLeftStepper   setIncrement: 2];
    [fCropLeftStepper   setMinValue:  0];
    [fCropRightStepper  setIncrement: 2];
    [fCropRightStepper  setMinValue:  0];
    
    /* we set the preview length popup in seconds */
    [fPreviewMovieLengthPopUp removeAllItems];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"5"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"10"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"15"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"20"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"25"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"30"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"35"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"40"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"45"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"50"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"55"];
    [fPreviewMovieLengthPopUp addItemWithTitle: @"60"];
    
    /* adjust the preview slider length */
    /* We use our advance pref to determine how many previews we scanned */
    int hb_num_previews = [[[NSUserDefaults standardUserDefaults] objectForKey:@"PreviewsNumber"] intValue];
    [fPictureSlider setMaxValue: hb_num_previews - 1.0];
    [fPictureSlider setNumberOfTickMarks: hb_num_previews];
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"PreviewLength"])
    {
        [fPreviewMovieLengthPopUp selectItemWithTitle:[[NSUserDefaults standardUserDefaults] objectForKey:@"PreviewLength"]];
    }
    else
    {
        /* currently hard set default to 10 seconds */
        [fPreviewMovieLengthPopUp selectItemAtIndex: 1];
    }
}

- (void) SetTitle: (hb_title_t *) title
{
    hb_job_t * job = title->job;

    fTitle = title;

    [fWidthStepper      setMaxValue: title->width];
    [fWidthStepper      setIntValue: job->width];
    [fWidthField        setIntValue: job->width];
    [fHeightStepper     setMaxValue: title->height];
    [fHeightStepper     setIntValue: job->height];
    [fHeightField       setIntValue: job->height];
    [fRatioCheck        setState:    job->keep_ratio ? NSOnState : NSOffState];
    [fCropTopStepper    setMaxValue: title->height/2-2];
    [fCropBottomStepper setMaxValue: title->height/2-2];
    [fCropLeftStepper   setMaxValue: title->width/2-2];
    [fCropRightStepper  setMaxValue: title->width/2-2];

    /* Populate the Anamorphic NSPopUp button here */
    [fAnamorphicPopUp removeAllItems];
    [fAnamorphicPopUp addItemWithTitle: @"None"];
    [fAnamorphicPopUp addItemWithTitle: @"Strict"];
    if (allowLooseAnamorphic)
    {
    [fAnamorphicPopUp addItemWithTitle: @"Loose"];
    }
    [fAnamorphicPopUp selectItemAtIndex: job->pixel_ratio];
    
    /* We initially set the previous state of keep ar to on */
    keepAspectRatioPreviousState = 1;
	if (!autoCrop)
	{
        [fCropMatrix  selectCellAtRow: 1 column:0];
        /* If auto, lets set the crop steppers according to current job->crop values */
        [fCropTopStepper    setIntValue: job->crop[0]];
        [fCropTopField      setIntValue: job->crop[0]];
        [fCropBottomStepper setIntValue: job->crop[1]];
        [fCropBottomField   setIntValue: job->crop[1]];
        [fCropLeftStepper   setIntValue: job->crop[2]];
        [fCropLeftField     setIntValue: job->crop[2]];
        [fCropRightStepper  setIntValue: job->crop[3]];
        [fCropRightField    setIntValue: job->crop[3]];
	}
	else
	{
        [fCropMatrix  selectCellAtRow: 0 column:0];
	}
	
	/* Set filters widgets according to the filters struct */
	[fDetelecineCheck setState:fPictureFilterSettings.detelecine];
    [fDeinterlacePopUp selectItemAtIndex: fPictureFilterSettings.deinterlace];
    [fDenoisePopUp selectItemAtIndex: fPictureFilterSettings.denoise];
    [fDeblockCheck setState: fPictureFilterSettings.deblock];
    [fDecombCheck setState: fPictureFilterSettings.decomb];
    
    fPicture = 0;
    MaxOutputWidth = title->width - job->crop[2] - job->crop[3];
    MaxOutputHeight = title->height - job->crop[0] - job->crop[1];
    [self SettingsChanged: nil];
}

/* we use this to setup the initial picture filters upon first launch, after that their states
are maintained across different sources */
- (void) setInitialPictureFilters
{
	/* we use a popup to show the deinterlace settings */
	[fDeinterlacePopUp removeAllItems];
    [fDeinterlacePopUp addItemWithTitle: @"None"];
    [fDeinterlacePopUp addItemWithTitle: @"Fast"];
    [fDeinterlacePopUp addItemWithTitle: @"Slow"];
	[fDeinterlacePopUp addItemWithTitle: @"Slower"];
    
	/* Set deinterlaces level according to the integer in the main window */
	[fDeinterlacePopUp selectItemAtIndex: fPictureFilterSettings.deinterlace];

	/* we use a popup to show the denoise settings */
	[fDenoisePopUp removeAllItems];
    [fDenoisePopUp addItemWithTitle: @"None"];
    [fDenoisePopUp addItemWithTitle: @"Weak"];
	[fDenoisePopUp addItemWithTitle: @"Medium"];
    [fDenoisePopUp addItemWithTitle: @"Strong"];
	/* Set denoises level according to the integer in the main window */
	[fDenoisePopUp selectItemAtIndex: fPictureFilterSettings.denoise];
    

}

// Adjusts the window to draw the current picture (fPicture) adjusting its size as
// necessary to display as much of the picture as possible.
- (void) displayPreview
{

    /* lets make sure that the still picture view is not hidden and that 
     * the movie preview is 
     */
    [fMovieView pause:nil];
    [fMovieView setHidden:YES];
    [fMovieCreationProgressIndicator stopAnimation: nil];
    [fMovieCreationProgressIndicator setHidden: YES];
    
    [fPictureView setHidden:NO];

    [fPictureView setImage: [self imageForPicture: fPicture]];
    	
	NSSize displaySize = NSMakeSize( ( CGFloat )fTitle->width, ( CGFloat )fTitle->height );
    /* Set the picture size display fields below the Preview Picture*/
    if( fTitle->job->pixel_ratio == 1 ) // Original PAR Implementation
    {
        output_width = fTitle->width-fTitle->job->crop[2]-fTitle->job->crop[3];
        output_height = fTitle->height-fTitle->job->crop[0]-fTitle->job->crop[1];
        display_width = output_width * fTitle->job->pixel_aspect_width / fTitle->job->pixel_aspect_height;
        [fInfoField setStringValue:[NSString stringWithFormat:
                                    @"Source: %dx%d, Output: %dx%d, Anamorphic: %dx%d",
                                    fTitle->width, fTitle->height, output_width, output_height, display_width, output_height]];
        displaySize.width *= ( ( CGFloat )fTitle->job->pixel_aspect_width ) / ( ( CGFloat )fTitle->job->pixel_aspect_height );   
    }
    else if (fTitle->job->pixel_ratio == 2) // Loose Anamorphic
    {
        display_width = output_width * output_par_width / output_par_height;
        [fInfoField setStringValue:[NSString stringWithFormat:
                                    @"Source: %dx%d, Output: %dx%d, Anamorphic: %dx%d",
                                    fTitle->width, fTitle->height, output_width, output_height, display_width, output_height]];
        
        displaySize.width = display_width;
    }
    else // No Anamorphic
    {
        [fInfoField setStringValue: [NSString stringWithFormat:
                                     @"Source: %dx%d, Output: %dx%d", fTitle->width, fTitle->height,
                                     fTitle->job->width, fTitle->job->height]];
    }

    NSSize viewSize = [self optimalViewSizeForImageSize:displaySize];
    if( [self viewNeedsToResizeToSize:viewSize] )
    {
        /* In the case of loose anamorphic, do not resize the window when scaling down */
        if (fTitle->job->pixel_ratio != 2 || [fWidthField intValue] == fTitle->width)
        {
            [self resizeSheetForViewSize:viewSize];
            [self setViewSize:viewSize];
        }
    }

    // Show the scaled text (use the height to check since the width can vary
    // with anamorphic video).
    if( ( ( int )viewSize.height ) != fTitle->height )
    {
        CGFloat scale = viewSize.width / ( ( CGFloat ) fTitle->width );
        NSString *scaleString = [NSString stringWithFormat:
                                 NSLocalizedString( @" (Preview scaled to %.0f%% actual size)",
                                                   @"String shown when a preview is scaled" ),
                                 scale * 100.0];
        [fInfoField setStringValue: [[fInfoField stringValue] stringByAppendingString:scaleString]];
    }

}

- (IBAction) previewDurationPopUpChanged: (id) sender
{

[[NSUserDefaults standardUserDefaults] setObject:[fPreviewMovieLengthPopUp titleOfSelectedItem] forKey:@"PreviewLength"];

}    
    
    

- (IBAction) deblockSliderChanged: (id) sender
{
    if ([fDeblockSlider floatValue] == 4.0)
    {
    [fDeblockField setStringValue: [NSString stringWithFormat: @"Off"]];
    }
    else
    {
    [fDeblockField setStringValue: [NSString stringWithFormat: @"%.0f", [fDeblockSlider floatValue]]];
    }
	[self SettingsChanged: sender];
}

- (IBAction) SettingsChanged: (id) sender
{
    hb_job_t * job = fTitle->job;
    
    autoCrop = ( [fCropMatrix selectedRow] == 0 );
    [fCropTopStepper    setEnabled: !autoCrop];
    [fCropBottomStepper setEnabled: !autoCrop];
    [fCropLeftStepper   setEnabled: !autoCrop];
    [fCropRightStepper  setEnabled: !autoCrop];

    if( autoCrop )
    {
        memcpy( job->crop, fTitle->crop, 4 * sizeof( int ) );
    }
    else
    {
        job->crop[0] = [fCropTopStepper    intValue];
        job->crop[1] = [fCropBottomStepper intValue];
        job->crop[2] = [fCropLeftStepper   intValue];
        job->crop[3] = [fCropRightStepper  intValue];
    }
    
	if( [fAnamorphicPopUp indexOfSelectedItem] > 0 )
	{
        if ([fAnamorphicPopUp indexOfSelectedItem] == 2) // Loose anamorphic
        {
            job->pixel_ratio = 2;
            [fWidthStepper setEnabled: YES];
            [fWidthField setEnabled: YES];
            /* We set job->width and call hb_set_anamorphic_size in libhb to do a "dry run" to get
             * the values to be used by libhb for loose anamorphic
             */
            /* if the sender is the anamorphic popup, then we know that loose anamorphic has just
             * been turned on, so snap the width to full width for the source.
             */
            if (sender == fAnamorphicPopUp)
            {
                [fWidthStepper      setIntValue: fTitle->width-fTitle->job->crop[2]-fTitle->job->crop[3]];
                [fWidthField        setIntValue: fTitle->width-fTitle->job->crop[2]-fTitle->job->crop[3]];
            }
            job->width       = [fWidthStepper  intValue];
            hb_set_anamorphic_size(job, &output_width, &output_height, &output_par_width, &output_par_height);
            [fHeightStepper      setIntValue: output_height];
            [fHeightField        setIntValue: output_height];
            job->height      = [fHeightStepper intValue];
            
        }
        else // must be "1" or strict anamorphic
        {
            [fWidthStepper      setIntValue: fTitle->width-fTitle->job->crop[2]-fTitle->job->crop[3]];
            [fWidthField        setIntValue: fTitle->width-fTitle->job->crop[2]-fTitle->job->crop[3]];
            
            /* This will show correct anamorphic height values, but
             show distorted preview picture ratio */
            [fHeightStepper      setIntValue: fTitle->height-fTitle->job->crop[0]-fTitle->job->crop[1]];
            [fHeightField        setIntValue: fTitle->height-fTitle->job->crop[0]-fTitle->job->crop[1]];
            job->width       = [fWidthStepper  intValue];
            job->height      = [fHeightStepper intValue];
            
            job->pixel_ratio = 1;
            [fWidthStepper setEnabled: NO];
            [fWidthField setEnabled: NO];
        }
        
        /* if the sender is the Anamorphic checkbox, record the state
         of KeepAspect Ratio so it can be reset if Anamorphic is unchecked again */
        if (sender == fAnamorphicPopUp)
        {
            keepAspectRatioPreviousState = [fRatioCheck state];
        }
        [fRatioCheck setState:NSOffState];
        [fRatioCheck setEnabled: NO];
        
        
        [fHeightStepper setEnabled: NO];
        [fHeightField setEnabled: NO];
        
    }
    else
	{
        job->width       = [fWidthStepper  intValue];
        job->height      = [fHeightStepper intValue];
        job->pixel_ratio = 0;
        [fWidthStepper setEnabled: YES];
        [fWidthField setEnabled: YES];
        [fHeightStepper setEnabled: YES];
        [fHeightField setEnabled: YES];
        [fRatioCheck setEnabled: YES];
        /* if the sender is the Anamorphic checkbox, we return the
         keep AR checkbox to its previous state */
        if (sender == fAnamorphicPopUp)
        {
            [fRatioCheck setState:keepAspectRatioPreviousState];
        }
        
	}
	
    job->keep_ratio  = ( [fRatioCheck state] == NSOnState );
    
	fPictureFilterSettings.deinterlace = [fDeinterlacePopUp indexOfSelectedItem];
    /* if the gui deinterlace settings are fast through slowest, the job->deinterlace
     value needs to be set to one, for the job as well as the previews showing deinterlacing
     otherwise set job->deinterlace to 0 or "off" */
    if (fPictureFilterSettings.deinterlace > 0)
    {
        job->deinterlace  = 1;
    }
    else
    {
        job->deinterlace  = 0;
    }
    fPictureFilterSettings.denoise     = [fDenoisePopUp indexOfSelectedItem];
    
    fPictureFilterSettings.detelecine  = [fDetelecineCheck state];
    
    if ([fDeblockField stringValue] == @"Off")
    {
    fPictureFilterSettings.deblock  = 0;
    }
    else
    {
    fPictureFilterSettings.deblock  = [fDeblockField intValue];
    }
    
    fPictureFilterSettings.decomb = [fDecombCheck state];

    if( job->keep_ratio )
    {
        if( sender == fWidthStepper || sender == fRatioCheck ||
           sender == fCropTopStepper || sender == fCropBottomStepper )
        {
            hb_fix_aspect( job, HB_KEEP_WIDTH );
            if( job->height > fTitle->height )
            {
                job->height = fTitle->height;
                hb_fix_aspect( job, HB_KEEP_HEIGHT );
            }
        }
        else
        {
            hb_fix_aspect( job, HB_KEEP_HEIGHT );
            if( job->width > fTitle->width )
            {
                job->width = fTitle->width;
                hb_fix_aspect( job, HB_KEEP_WIDTH );
            }
        }
        // hb_get_preview can't handle sizes that are larger than the original title
        // dimensions
        if( job->width > fTitle->width )
            job->width = fTitle->width;

        if( job->height > fTitle->height )
            job->height = fTitle->height;
    }

    [fWidthStepper      setIntValue: job->width];
    [fWidthField        setIntValue: job->width];
    if( [fAnamorphicPopUp indexOfSelectedItem] < 2 )
	{
        [fHeightStepper     setIntValue: job->height];
        [fHeightField       setIntValue: job->height];
    }
    [fCropTopStepper    setIntValue: job->crop[0]];
    [fCropTopField      setIntValue: job->crop[0]];
    [fCropBottomStepper setIntValue: job->crop[1]];
    [fCropBottomField   setIntValue: job->crop[1]];
    [fCropLeftStepper   setIntValue: job->crop[2]];
    [fCropLeftField     setIntValue: job->crop[2]];
    [fCropRightStepper  setIntValue: job->crop[3]];
    [fCropRightField    setIntValue: job->crop[3]];
    /* Sanity Check Here for < 16 px preview to avoid
     crashing hb_get_preview. In fact, just for kicks
     lets getting previews at a min limit of 32, since
     no human can see any meaningful detail below that */
    if (job->width >= 64 && job->height >= 64)
    {
       
         // Purge the existing picture previews so they get recreated the next time
        // they are needed.
        [self purgeImageCache];
        /* We actually call displayPreview now from pictureSliderChanged which keeps
         * our picture preview slider in sync with the previews being shown
         */
        //[self displayPreview];
        [self pictureSliderChanged:nil];

    }

    if (sender != nil)
    {
        if ([delegate respondsToSelector:@selector(pictureSettingsDidChange)])
            [delegate pictureSettingsDidChange];
    }   
    
}

- (IBAction) pictureSliderChanged: (id) sender
{
    // Show the picture view
    [fCreatePreviewMovieButton setTitle: @"Live Preview"];
    [fPictureView setHidden:NO];
    [fMovieView pause:nil];
    [fMovieView setHidden:YES];
    [fPreviewMovieStatusField setHidden: YES];
    
    int newPicture = [fPictureSlider intValue];
    if (newPicture != fPicture)
    {
        fPicture = newPicture;
    }
    [self displayPreview];
    
}

#pragma mark Movie Preview
- (IBAction) createMoviePreview: (id) sender
{
    /* Lets make sure the still picture previews are showing in case
     * there is currently a movie showing */
    [self pictureSliderChanged:nil];
    
    /* Rip or Cancel ? */
    hb_state_t s;
    hb_get_state2( fPreviewLibhb, &s );
    
    if(s.state == HB_STATE_WORKING || s.state == HB_STATE_PAUSED)
	{
        
        play_movie = NO;
        hb_stop( fPreviewLibhb );
        [fPictureView setHidden:NO];
        [fMovieView pause:nil];
        [fMovieView setHidden:YES];
        [fPictureSlider setHidden:NO];
        [fCreatePreviewMovieButton setTitle: @"Live Preview"];
        return;
    }
    
    /* we use controller.mm's prepareJobForPreview to go ahead and set all of our settings
     * however, we want to use a temporary destination field of course
     * so that we do not put our temp preview in the users chosen
     * directory */
    
    hb_job_t * job = fTitle->job;
    /* We run our current setting through prepeareJob in Controller.mm
     * just as if it were a regular encode */
    if ([delegate respondsToSelector:@selector(prepareJobForPreview)])
    {
        [delegate prepareJobForPreview];
    }
    
    /* Destination file. We set this to our preview directory
     * changing the extension appropriately.*/
    if (fTitle->job->mux == HB_MUX_MP4) // MP4 file
    {
        /* we use .m4v for our mp4 files so that ac3 and chapters in mp4 will play properly */
        fPreviewMoviePath = @"~/Library/Application Support/HandBrake/Previews/preview_temp.m4v";
    }
    else if (fTitle->job->mux == HB_MUX_MKV) // MKV file
    {
        fPreviewMoviePath = @"~/Library/Application Support/HandBrake/Previews/preview_temp.mkv";
    }
    else if (fTitle->job->mux == HB_MUX_AVI) // AVI file
    {
        fPreviewMoviePath = @"~/Library/Application Support/HandBrake/Previews/preview_temp.avi";
    }
    else if (fTitle->job->mux == HB_MUX_OGM) // OGM file
    {
        fPreviewMoviePath = @"~/Library/Application Support/HandBrake/Previews/preview_temp.ogm";
    }
    
    fPreviewMoviePath = [[fPreviewMoviePath stringByExpandingTildeInPath]retain];
    
    /* See if there is an existing preview file, if so, delete it */
    if( ![[NSFileManager defaultManager] fileExistsAtPath:fPreviewMoviePath] )
    {
        [[NSFileManager defaultManager] removeFileAtPath:fPreviewMoviePath
                                                 handler:nil];
    }
    
    /* We now direct our preview encode to fPreviewMoviePath */
    fTitle->job->file = [fPreviewMoviePath UTF8String];
    
    /* We use our advance pref to determine how many previews to scan */
    int hb_num_previews = [[[NSUserDefaults standardUserDefaults] objectForKey:@"PreviewsNumber"] intValue];
    job->start_at_preview = fPicture + 1;
    job->seek_points = hb_num_previews;
    
    /* we use the preview duration popup to get the specified
     * number of seconds for the preview encode.
     */
    
    job->pts_to_stop = [[fPreviewMovieLengthPopUp titleOfSelectedItem] intValue] * 90000LL;
    
    /* lets go ahead and send it off to libhb
     * Note: unlike a full encode, we only send 1 pass regardless if the final encode calls for 2 passes.
     * this should suffice for a fairly accurate short preview and cuts our preview generation time in half.
     */
    hb_add( fPreviewLibhb, job );
    
    [fPictureSlider setHidden:YES];
    [fMovieCreationProgressIndicator setHidden: NO];
    [fPreviewMovieStatusField setHidden: NO];
    [self startReceivingLibhbNotifications];
    
    
    [fCreatePreviewMovieButton setTitle: @"Cancel Preview"];
    
    play_movie = YES;
    
    /* Let fPreviewLibhb do the job */
    hb_start( fPreviewLibhb );
	
}

- (void) startReceivingLibhbNotifications
{
    if (!fLibhbTimer)
    {
        fLibhbTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(libhbTimerFired:) userInfo:nil repeats:YES];
        [fLibhbTimer retain];
    }
}

- (void) stopReceivingLibhbNotifications
{
    if (fLibhbTimer)
    {
        [fLibhbTimer invalidate];
        [fLibhbTimer release];
        fLibhbTimer = nil;
    }
}
- (void) libhbTimerFired: (NSTimer*)theTimer
{
    hb_state_t s;
    hb_get_state( fPreviewLibhb, &s );
    [self libhbStateChanged: s];
}
- (void) libhbStateChanged: (hb_state_t &)state
{
    switch( state.state )
    {
        case HB_STATE_IDLE:
        case HB_STATE_SCANNING:
        case HB_STATE_SCANDONE:
            break;
            
        case HB_STATE_WORKING:
        {
#define p state.param.working
            
            NSMutableString * string;
			/* Update text field */
			string = [NSMutableString stringWithFormat: NSLocalizedString( @"Encoding %d seconds of preview %d:  %.2f %%", @"" ), [[fPreviewMovieLengthPopUp titleOfSelectedItem] intValue], fPicture + 1, 100.0 * p.progress];
            
			if( p.seconds > -1 )
            {
                [string appendFormat:
                 NSLocalizedString( @" (%.2f fps, avg %.2f fps, ETA %02dh%02dm%02ds)", @"" ),
                 p.rate_cur, p.rate_avg, p.hours, p.minutes, p.seconds];
            }
            [fPreviewMovieStatusField setStringValue: string];
            
            [fMovieCreationProgressIndicator setIndeterminate: NO];
            /* Update slider */
			[fMovieCreationProgressIndicator setDoubleValue: 100.0 * p.progress];
            
            [fCreatePreviewMovieButton setTitle: @"Cancel Preview"];
            
            break;
            
        }
#undef p
            
#define p state.param.muxing            
        case HB_STATE_MUXING:
        {
            // Update fMovieCreationProgressIndicator
            [fMovieCreationProgressIndicator setIndeterminate: YES];
            [fMovieCreationProgressIndicator startAnimation: nil];
            [fPreviewMovieStatusField setStringValue: [NSString stringWithFormat:
                                         NSLocalizedString( @"Muxing Preview ...", @"" )]];
            break;
        }
#undef p			
        case HB_STATE_PAUSED:
            [fMovieCreationProgressIndicator stopAnimation: nil];
            break;
			
        case HB_STATE_WORKDONE:
        {
            // Delete all remaining jobs since libhb doesn't do this on its own.
            hb_job_t * job;
            while( ( job = hb_job(fPreviewLibhb, 0) ) )
                hb_rem( fHandle, job );
            
            [self stopReceivingLibhbNotifications];
            [fPreviewMovieStatusField setStringValue: @""];
            [fPreviewMovieStatusField setHidden: YES];
            
            [fMovieCreationProgressIndicator stopAnimation: nil];
            [fMovieCreationProgressIndicator setHidden: YES];
            /* we make sure the picture slider and preview match */
            [self pictureSliderChanged:nil];
            [fPictureSlider setHidden:NO];
            
            // Show the movie view
            if (play_movie)
            {
            [self showMoviePreview:fPreviewMoviePath];
            }
            
            [fCreatePreviewMovieButton setTitle: @"Live Preview"];
            
            
            break;
        }
    }
	
}

- (IBAction) showMoviePreview: (NSString *) path
{
    /* Since the gray background for the still images is part of
     * fPictureView, lets leave the picture view visible and postion
     * the fMovieView over the image portion of fPictureView so
     * we retain the gray cropping border  we have already established
     * with the still previews
     */
    [fMovieView setHidden:NO];
    
    /* Load the new movie into fMovieView */
    QTMovie * aMovie;
    NSRect movieBounds;
    if (path)
    {
        [fMovieView setControllerVisible: YES];
        /* let's make sure there is no movie currently set */
        [fMovieView setMovie:nil];
        
        aMovie = [QTMovie movieWithFile:path error:nil];
        
        /* we get some size information from the preview movie */
        Rect movieBox;
        GetMovieBox ([aMovie quickTimeMovie], &movieBox);
        movieBounds = [fMovieView movieBounds];
        movieBounds.size.height = movieBox.bottom - movieBox.top;
        
        if ([fMovieView isControllerVisible])
            movieBounds.size.height += [fMovieView controllerBarHeight];
        /* since for whatever the reason I cannot seem to get the [fMovieView controllerBarHeight]
         * For now just use 15 for additional height as it seems to line up well
         */
        movieBounds.size.height += 15;
        
        movieBounds.size.width = movieBox.right - movieBox.left;
        
        /* We need to find out if the preview movie needs to be scaled down so
         * that it doesn't overflow our available viewing container (just like for image
         * in -displayPreview) for HD sources, etc. [fPictureViewArea frame].size.height*/
        if( ((int)movieBounds.size.height) > [fPictureView frame].size.height )
        {
            /* The preview movie would be larger than the available viewing area
             * in the preview movie, so we go ahead and scale it down to the same size
             * as the still preview  or we readjust our window to allow for the added height if need be
             */
            NSSize displaySize = NSMakeSize( (float)movieBounds.size.width, (float)movieBounds.size.height );
            //NSSize displaySize = NSMakeSize( (float)fTitle->width, (float)fTitle->height );
            NSSize viewSize = [self optimalViewSizeForImageSize:displaySize];
            if( [self viewNeedsToResizeToSize:viewSize] )
            {
                
                [self resizeSheetForViewSize:viewSize];
                [self setViewSize:viewSize];
                
            }
            
            [fMovieView setFrameSize:viewSize];
        }
        else
        {
            /* Since the preview movie is smaller than the available viewing area
             * we can go ahead and use the preview movies native size */
            [fMovieView setFrameSize:movieBounds.size];
        }
        
        // lets reposition the movie if need be
        
        NSPoint origin = [fPictureViewArea frame].origin;
        origin.x += trunc(([fPictureViewArea frame].size.width -
                           [fMovieView frame].size.width) / 2.0);
        /* We need to detect whether or not we are currently less than the available height.*/
        if (movieBounds.size.height < [fPictureView frame].size.height)
        {
        /* If we are, we are adding 15 to the height to allow for the controller bar so
         * we need to subtract half of that for the origin.y to get the controller bar
         * below the movie to it lines up vertically with where our still preview was
         */
        origin.y += trunc((([fPictureViewArea frame].size.height -
                            [fMovieView frame].size.height) / 2.0) - 7.5);
        }
        else
        {
        /* if we are >= to the height of the picture view area, the controller bar
         * gets taken care of with picture resizing, so we do not want to offset the height
         */
        origin.y += trunc(([fPictureViewArea frame].size.height -
                            [fMovieView frame].size.height) / 2.0);
        }
        [fMovieView setFrameOrigin:origin]; 
        
        [fMovieView setMovie:aMovie];
        /// to actually play the movie
        [fMovieView play:aMovie];
    }
    else
    {
        aMovie = nil;
    }       
    
}

#pragma mark -

- (IBAction) ClosePanel: (id) sender
{
    if ([delegate respondsToSelector:@selector(pictureSettingsDidChange)])
        [delegate pictureSettingsDidChange];

    [NSApp endSheet:[self window]];
    [[self window] orderOut:self];
}

- (BOOL) autoCrop
{
    return autoCrop;
}
- (void) setAutoCrop: (BOOL) setting
{
    autoCrop = setting;
}

- (BOOL) allowLooseAnamorphic
{
    return allowLooseAnamorphic;
}

- (void) setAllowLooseAnamorphic: (BOOL) setting
{
    allowLooseAnamorphic = setting;
}

- (int) detelecine
{
    return fPictureFilterSettings.detelecine;
}

- (void) setDetelecine: (int) setting
{
    fPictureFilterSettings.detelecine = setting;
}

- (int) deinterlace
{
    return fPictureFilterSettings.deinterlace;
}

- (void) setDeinterlace: (int) setting {
    fPictureFilterSettings.deinterlace = setting;
}
- (int) decomb
{
    return fPictureFilterSettings.decomb;
}

- (void) setDecomb: (int) setting {
    fPictureFilterSettings.decomb = setting;
}
- (int) denoise
{
    return fPictureFilterSettings.denoise;
}

- (void) setDenoise: (int) setting
{
    fPictureFilterSettings.denoise = setting;
}

- (int) deblock
{
    return fPictureFilterSettings.deblock;
}

- (void) setDeblock: (int) setting
{
    fPictureFilterSettings.deblock = setting;
}

- (IBAction)showPreviewPanel: (id)sender forTitle: (hb_title_t *)title
{
    [self SetTitle:title];
    [self showWindow:sender];

}


// This function converts an image created by libhb (specified via pictureIndex) into
// an NSImage suitable for the GUI code to use. If removeBorders is YES,
// makeImageForPicture crops the image generated by libhb stripping off the gray
// border around the content. This is the low-level method that generates the image.
// -imageForPicture calls this function whenever it can't find an image in its cache.
+ (NSImage *) makeImageForPicture: (int)pictureIndex
                libhb:(hb_handle_t*)handle
                title:(hb_title_t*)title
                removeBorders:(BOOL)removeBorders
{
    if (removeBorders)
    {
        //     |<---------- title->width ----------->|
        //     |   |<---- title->job->width ---->|   |
        //     |   |                             |   |
        //     .......................................
        //     ....+-----------------------------+....
        //     ....|                             |....<-- gray border
        //     ....|                             |....
        //     ....|                             |....
        //     ....|                             |<------- image
        //     ....|                             |....
        //     ....|                             |....
        //     ....|                             |....
        //     ....|                             |....
        //     ....|                             |....
        //     ....+-----------------------------+....
        //     .......................................

        static uint8_t * buffer;
        static int bufferSize;

        // Make sure we have a big enough buffer to receive the image from libhb. libhb
        // creates images with a one-pixel border around the original content. Hence we
        // add 2 pixels horizontally and vertically to the buffer size.
        int srcWidth = title->width + 2;
        int srcHeight= title->height + 2;
        int newSize;
        newSize = srcWidth * srcHeight * 4;
        if( bufferSize < newSize )
        {
            bufferSize = newSize;
            buffer     = (uint8_t *) realloc( buffer, bufferSize );
        }

        hb_get_preview( handle, title, pictureIndex, buffer );

        // Create an NSBitmapImageRep and copy the libhb image into it, converting it from
        // libhb's format to one suitable for NSImage. Along the way, we'll strip off the
        // border around libhb's image.
        
        // The image data returned by hb_get_preview is 4 bytes per pixel, BGRA format.
        // Alpha is ignored.
        
        int dstWidth = title->job->width;
        int dstHeight = title->job->height;
        NSBitmapFormat bitmapFormat = (NSBitmapFormat)NSAlphaFirstBitmapFormat;
        NSBitmapImageRep * imgrep = [[[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:nil
                pixelsWide:dstWidth
                pixelsHigh:dstHeight
                bitsPerSample:8
                samplesPerPixel:3   // ignore alpha
                hasAlpha:NO
                isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace
                bitmapFormat:bitmapFormat
                bytesPerRow:dstWidth * 4
                bitsPerPixel:32] autorelease];

        int borderTop = (srcHeight - dstHeight) / 2;
        int borderLeft = (srcWidth - dstWidth) / 2;
        
        UInt32 * src = (UInt32 *)buffer;
        UInt32 * dst = (UInt32 *)[imgrep bitmapData];
        src += borderTop * srcWidth;    // skip top rows in src to get to first row of dst
        src += borderLeft;              // skip left pixels in src to get to first pixel of dst
        for (int r = 0; r < dstHeight; r++)
        {
            for (int c = 0; c < dstWidth; c++)
#if TARGET_RT_LITTLE_ENDIAN
                *dst++ = Endian32_Swap(*src++);
#else
                *dst++ = *src++;
#endif
            src += (srcWidth - dstWidth);   // skip to next row in src
        }

        NSImage * img = [[[NSImage alloc] initWithSize: NSMakeSize(dstWidth, dstHeight)] autorelease];
        [img addRepresentation:imgrep];

        return img;
    }
    else
    {
        // Make sure we have big enough buffer
        static uint8_t * buffer;
        static int bufferSize;

        int newSize;
        newSize = ( title->width + 2 ) * (title->height + 2 ) * 4;
        if( bufferSize < newSize )
        {
            bufferSize = newSize;
            buffer     = (uint8_t *) realloc( buffer, bufferSize );
        }

        hb_get_preview( handle, title, pictureIndex, buffer );

        // The image data returned by hb_get_preview is 4 bytes per pixel, BGRA format.
        // We'll copy that into an NSImage swapping it to ARGB in the process. Alpha is
        // ignored.
        int width = title->width + 2;      // hblib adds a one-pixel border to the image
        int height = title->height + 2;
        int numPixels = width * height;
        NSBitmapFormat bitmapFormat = (NSBitmapFormat)NSAlphaFirstBitmapFormat;
        NSBitmapImageRep * imgrep = [[[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:nil
                pixelsWide:width
                pixelsHigh:height
                bitsPerSample:8
                samplesPerPixel:3   // ignore alpha
                hasAlpha:NO
                isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace
                bitmapFormat:bitmapFormat
                bytesPerRow:width * 4
                bitsPerPixel:32] autorelease];

        UInt32 * src = (UInt32 *)buffer;
        UInt32 * dst = (UInt32 *)[imgrep bitmapData];
        for (int i = 0; i < numPixels; i++)
#if TARGET_RT_LITTLE_ENDIAN
            *dst++ = Endian32_Swap(*src++);
#else
            *dst++ = *src++;
#endif

        NSImage * img = [[[NSImage alloc] initWithSize: NSMakeSize(width, height)] autorelease];
        [img addRepresentation:imgrep];

        return img;
    }
}

// Returns the preview image for the specified index, retrieving it from its internal
// cache or by calling makeImageForPicture if it is not cached. Generally, you should
// use imageForPicture so that images are cached. Calling makeImageForPicture will
// always generate a new copy of the image.
- (NSImage *) imageForPicture: (int) pictureIndex
{
    // The preview for the specified index may not currently exist, so this method
    // generates it if necessary.
    NSString * key = [NSString stringWithFormat:@"%d", pictureIndex];
    NSImage * theImage = [fPicturePreviews objectForKey:key];
    if (!theImage)
    {
        theImage = [PictureController makeImageForPicture:pictureIndex libhb:fHandle title:fTitle removeBorders: NO];
        [fPicturePreviews setObject:theImage forKey:key];
    }
    return theImage;
}

// Purges all images from the cache. The next call to imageForPicture will cause a new
// image to be generated.
- (void) purgeImageCache
{
    [fPicturePreviews removeAllObjects];
}

@end

@implementation PictureController (Private)

//
// -[PictureController(Private) optimalViewSizeForImageSize:]
//
// Given the size of the preview image to be shown, returns the best possible
// size for the view.
//
- (NSSize)optimalViewSizeForImageSize: (NSSize)imageSize
{
    // The min size is 320x240
    CGFloat minWidth = 320.0;
    CGFloat minHeight = 240.0;

    NSSize screenSize = [[NSScreen mainScreen] frame].size;
    NSSize sheetSize = [[self window] frame].size;
    NSSize viewAreaSize = [fPictureViewArea frame].size;
    CGFloat paddingX = sheetSize.width - viewAreaSize.width;
    CGFloat paddingY = sheetSize.height - viewAreaSize.height;
    /* Since we are now non-modal, lets go ahead and allow the mac size to
     * go up to the full screen height or width below. Am leaving the original
     * code here that blindjimmy setup for 85% in case we don't like it.
     */
    // The max size of the view is when the sheet is taking up 85% of the screen.
    //CGFloat maxWidth = (0.85 * screenSize.width) - paddingX;
    //CGFloat maxHeight = (0.85 * screenSize.height) - paddingY;
    CGFloat maxWidth =  screenSize.width - paddingX;
    CGFloat maxHeight = screenSize.height - paddingY;
    
    NSSize resultSize = imageSize;
    
    // Its better to have a view that's too small than a view that's too big, so
    // apply the maximum constraints last.
    if( resultSize.width < minWidth )
    {
        resultSize.height *= (minWidth / resultSize.width);
        resultSize.width = minWidth;
    }
    if( resultSize.height < minHeight )
    {
        resultSize.width *= (minHeight / resultSize.height);
        resultSize.height = minHeight;
    }
    if( resultSize.width > maxWidth )
    {
        resultSize.height *= (maxWidth / resultSize.width);
        resultSize.width = maxWidth;
    }
    if( resultSize.height > maxHeight )
    {
        resultSize.width *= (maxHeight / resultSize.height);
        resultSize.height = maxHeight;
    }
    
    return resultSize;
}

//
// -[PictureController(Private) resizePanelForViewSize:animate:]
//
// Resizes the entire sheet to accomodate a view of a particular size.
//
- (void)resizeSheetForViewSize: (NSSize)viewSize
{
    // Figure out the deltas for the new frame area
    NSSize currentSize = [fPictureViewArea frame].size;
    CGFloat deltaX = viewSize.width - currentSize.width;
    CGFloat deltaY = viewSize.height - currentSize.height;

    // Now resize the whole panel by those same deltas, but don't exceed the min
    NSRect frame = [[self window] frame];
    NSSize maxSize = [[self window] maxSize];
    NSSize minSize = [[self window] minSize];
    frame.size.width += deltaX;
    frame.size.height += deltaY;
    if( frame.size.width < minSize.width )
    {
        frame.size.width = minSize.width;
    }
    if( frame.size.height < minSize.height )
    {
        frame.size.height = minSize.height;
    }

    // But now the sheet is off-center, so also shift the origin to center it and
    // keep the top aligned.
    if( frame.size.width != [[self window] frame].size.width )
        frame.origin.x -= (deltaX / 2.0);

    if( frame.size.height != [[self window] frame].size.height )
        frame.origin.y -= deltaY;

    [[self window] setFrame:frame display:YES animate:YES];
}

//
// -[PictureController(Private) setViewSize:]
//
// Changes the view's size and centers it vertically inside of its area.
// Assumes resizeSheetForViewSize: has already been called.
//
- (void)setViewSize: (NSSize)viewSize
{
    [fPictureView setFrameSize:viewSize];
    
    // center it vertically
    NSPoint origin = [fPictureViewArea frame].origin;
    origin.y += ([fPictureViewArea frame].size.height -
                 [fPictureView frame].size.height) / 2.0;
    [fPictureView setFrameOrigin:origin];
}

//
// -[PictureController(Private) viewNeedsToResizeToSize:]
//
// Returns YES if the view will need to resize to match the given size.
//
- (BOOL)viewNeedsToResizeToSize: (NSSize)newSize
{
    NSSize viewSize = [fPictureView frame].size;
    return (newSize.width != viewSize.width || newSize.height != viewSize.height);
}

@end
