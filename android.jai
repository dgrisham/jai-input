update_window_events :: () {
    if !initted {
        defer initted = true;

        // Bit of a @Hack. It is common for desktop apps to have window width/height variables set at start up
        // and request a window of that size. On android this doesn't make any sense and we ignore the
        // width/height passed to create_window, but then we need to update the programs variables.
        // Just triggering a window resize event here will make existing apps just work, but maybe it's not
        // so smart!
        assert(context.android_app != null && context.android_app.window != null);
        add_resize_record(context.android_app.window);
    }

    input_per_frame_event_and_flag_update();

    android_process_events();
}

android_process_events :: () {
    while true {
        ident, events: s32;
        source: *Native_App.Android_Poll_Source;
        // Read all pending events. If app is not in focus we block here (timeout == -1) as we don't want to tick
        // till we have a window!
        timeout := ifx android_in_focus  0 else -1;
        ident = ALooper_pollAll(xx timeout, null, *events, cast(**void)*source);
        if ident < 0 break;

        // Process this event.
        assert(source != null, "android_poll_source for identifier % was null. This is no good!", ident);
        source.process(context.android_app, source);

        // Check if we are exiting.
        if context.android_app.destroyRequested {
            log("Destroy requested"); // @Incomplete!
            event: Event;
            event.type = .QUIT;
            array_add(*events_this_frame, event);
            break;
        }
    }
}

set_custom_cursor_handling :: (is_custom: bool) {}

// I did some pointer stuff in onscreen_controls.jai for invaders. Probably gonna just put that in here
// at some point. Not sure atm how to do it usefully. For now this module just handles one finger that
// emulates being a mouse.
// - Charles

handle_input_event :: (event: *AInputEvent) -> bool {
    Window_Creation :: #import "Window_Creation"; // @Hack

    if AInputEvent_getType(event) == .MOTION {
        action := cast(AMOTION_EVENT_ACTION) AMotionEvent_getAction(event);
        android_num_pointers = xx AMotionEvent_getPointerCount(event); // @Tmp

        window_height := ANativeWindow_getHeight(context.android_app.window);

        new_x := AMotionEvent_getX(event, 0);
        new_y := window_height - AMotionEvent_getY(event, 0);
        Window_Creation.touch_x = xx new_x;
        Window_Creation.touch_y = xx new_y;

        // If less than zero we weren't touching last frame => delta is zero.
        if last_touch_x >= 0 {
            mouse_delta_x = xx (new_x - last_touch_x);
            mouse_delta_y = xx (new_y - last_touch_y);
        }

        last_touch_x = new_x;
        last_touch_y = new_y;

        if action == {
            case .DOWN;
                event: Event;
                event.type = .KEYBOARD;
                event.key_pressed = 1;
                event.key_code = .MOUSE_BUTTON_LEFT;
                array_add(*events_this_frame, event);

                input_button_states[Key_Code.MOUSE_BUTTON_LEFT] = (Key_Current_State.DOWN | .START);

            case .UP;
                event: Event;
                event.type = .KEYBOARD;
                event.key_pressed = 0;
                event.key_code = .MOUSE_BUTTON_LEFT;
                array_add(*events_this_frame, event);

                input_button_states[Key_Code.MOUSE_BUTTON_LEFT] = .END;

                last_touch_x, last_touch_y = -1.;
        }

        return true;
    }

    return false;
}

//
// @Incomplete :AndroidLifeCycle
//
// For an android app to be well behaved additional command handling is required. Eg, when an app goes in/out out of
// focus you are required to create/destroy it's egl context, see example at https://github.com/android/ndk-samples/blob/master/native-activity/app/src/main/cpp/main.cpp
//
// It is unclear how much should be handled in this module vs leaving it up to the user's app.
handle_command :: (app: *Native_App.Android_App, cmd: s32) {
    command := cast(Native_App.APP_CMD) cmd;
    log("Command received: %", command);

    if #complete command == {
        // The window is being shown, get it ready.
        case .INIT_WINDOW;
            android_in_focus = true;
            w := ANativeWindow_getWidth(app.window);
            h := ANativeWindow_getHeight(app.window);
            log("Window inited. It's size is (%, %).", w, h);

        // The window is being hidden or closed, clean it up.
        case .TERM_WINDOW;
            android_in_focus = false;
            // deinit_window();

        case .GAINED_FOCUS;
            android_in_focus = true;

        case .LOST_FOCUS;
            android_in_focus = false;

        case .CONTENT_RECT_CHANGED;
            log("Content rect is now: %", app.contentRect);

        case .INPUT_CHANGED; #through;
        case .WINDOW_RESIZED; #through;
        case .WINDOW_REDRAW_NEEDED; #through;
        case .CONFIG_CHANGED; #through;
        case .LOW_MEMORY; #through;
        case .START; #through;
        case .RESUME; #through;
        case .SAVE_STATE; #through;
        case .PAUSE; #through;
        case .STOP; #through;
        case .DESTROY;
            log("Command % not currently handled!", command, flags = .WARNING);
    }
}

android_in_focus: bool;


#scope_file

// @CopyPasta from Input/windows.jai
add_resize_record :: (window: *ANativeWindow) {
    record: *Window_Resize_Record;
    for * pending_resizes {
        if it.window == window {
            record = it;
            break;
        }
    }

    if !record {
        record = array_add(*pending_resizes);
        this_allocation_is_not_a_leak(pending_resizes.data); // :ScanGlobalData
    }

    width  := ANativeWindow_getWidth(window);
    height := ANativeWindow_getHeight(window);

    record.window = window;
    record.width  = width;
    record.height = height;
}

initted := false;

#import "Android";
Native_App :: #import "Android/Native_App";

last_touch_x, last_touch_y := -1.;

// @Tmp allows skel anim to do different things for 2 finger touch. Will probably want something more general for
// touch input.
#scope_export
android_num_pointers := 0;
