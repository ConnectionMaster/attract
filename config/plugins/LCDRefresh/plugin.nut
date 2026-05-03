// LCDRefresh Attract-Mode Plugin (c) 2026 Andrew Mickelson
//
class UserConfig </ help="Plugin for blanking the screen and/or setting custom refresh rates on LCD screens" /> {
	</ label="Blank Screen",
			help="Blank screen when launching emulator?",
			order=1,
			options="Yes,No" />
	blank_screen="Yes";

	</ label="Delay (in milliseconds)",
			help="Set a delay before blanking the screen or setting the refresh rate.  You may want to do this if you have fancy transition effects to run before launching the emulator",
			order=2 />
	delay=0;


	</ label="Emulator(s)",
			help="Emulator(s) to switch refresh rate for (comma separated, leave blank for all)",
			order=3 />
	emulators="mame";

	</ label="Minimum Refresh Hz",
		help="Minimum refresh rate supported by the monitor (in Hz)",
		order=4 />
	min_hz="55.5";

	</ label="Maximum Refresh Hz",
		help="Maximum refresh rate supported by the monitor (in Hz)",
		order=5 />
	max_hz="75";

	</ label="Vector Refresh Hz",
			help="Refresh rate for vector games",
			order=6 />
	vector_hz="75";

	</ label="Default Refresh Hz",
		help="The default refresh rate",
		order=7 />
	default_hz="60";

	</ label="Command",
		help="Command line to set a custom refresh rate (%RATE% gets replaced with the actual rate value)",
		order=8 />
	command="wlr-randr --output HDMI-A-1 --custom-mode 1280x1024@%RATE%";

	</ label="Out of range strategy",
			help="Set what to do when out of range.",
			order=9,
			options="clamp,use_default,clamp_min_only,clamp_max_only" />
	strategy="clamp";

	</ label="Show Audit",
			help="List games falling outside of the min/max refresh range to the console.",
			order=10,
			options="Yes,No" />
	show_audit="No";
}

const DE_MINIMUS=0.1;

class LCDRefresh
{
	my_config=null;
	min_hz=0.0;
	max_hz=0.0;
	vector_hz=0.0;
	default_hz=0.0;
	last_set_rate="";
	set_game_refresh=false;
	blank_screen=null;
	one_time=true;
	do_audit=false;
	delay=0;

	constructor()
	{
		my_config = fe.get_config();

		min_hz = my_config["min_hz"].tofloat();

		max_hz = my_config["max_hz"].tofloat();
		if ( max_hz<0.5 ) max_hz=32000; // if no max_hz set then use a high value

		if ( my_config["vector_hz"].len() > 0 )
			vector_hz = my_config["vector_hz"].tofloat();

		default_hz = my_config["default_hz"].tofloat();

		if ( my_config["blank_screen"] == "Yes" )
		{
			blank_screen = fe.add_image("1x1black.png");
			blank_screen.visible=false;
		}

		fe.add_transition_callback( this, "on_transition" );

		do_audit = ( my_config["show_audit"] == "Yes" );

		delay = my_config["delay"].tointeger();
	}

	function my_repl( src, target, repl )
	{
		local pos = src.find( target );
		if ( pos == null )
			return src;

		local temp = src.slice( 0, pos );
		temp += repl;

		if ( src.len() > pos + target.len() )
			temp += src.slice( pos + target.len() );

		return temp;
	}

	function run_cmd( rstring )
	{
		local cmd = my_repl( my_config["command"], "%RATE%", rstring );

		print( "LCDRefresh: Running '"
			+ cmd + "' ["
			+ fe.game_info( Info.Name ) + ", "
			+ fe.game_info( Info.DisplayRefresh ) + "]\n" );

		system( cmd );
	}

	// return the refresh rate that can actually used, or 0 if there isn't one
	//
	function calculate_refresh( offset=0 )
	{
		if ( my_config["emulators"].len() > 0 )
		{
			if ( my_config["emulators"].find( fe.game_info( Info.Emulator, offset ) ) == null )
				return 0;
		}

 		if ( fe.game_info( Info.DisplayType, offset ) == "vector" )
			return vector_hz;

		local rr = fe.game_info( Info.DisplayRefresh, offset );
		if ( rr.len() < 1 )
			return 0;

		local r=rr.tofloat();
		if ( r < min_hz )
		{
			// first check if a double up works
			local fix=r*2;
			if (( fix >= min_hz ) && ( fix <= max_hz ))
				r = fix;
			else
			{
				if (( my_config["strategy"]=="clamp" )
					|| ( my_config["strategy"]=="clamp_min_only" ))
					r = min_hz;
				else
					return 0;
			}
		}
		if ( r > max_hz )
		{
			if (( my_config["strategy"]=="clamp" )
					|| ( my_config["strategy"]=="clamp_max_only" ))
				r = max_hz;
			else
				return 0;
		}

		// don't do anything if r is essentially the same as the default refresh
		//
		if (( r < default_hz + DE_MINIMUS ) && ( r > default_hz - DE_MINIMUS ))
			return 0

		return r;
	}

	function on_transition( ttype, var, ttime )
	{
		if ( ScreenSaverActive )
			return false;

		switch ( ttype )
		{
		case Transition.ToGame:
			//
			// Delay
			//
			if ( ttime < delay )
				return true;

			//
			// Screen blanking
			//
			if ( blank_screen )
			{
				blank_screen.set_pos(0,0.fe.layout.width,fe.layout.height);
				blank_screen.zorder=68000;
				blank_screen.visible=true;
				if ( one_time )
				{
					// return "true" one time to make the frontend redraw the screen
					// before we finish the transition (and have the game launch)
					//
					one_time = false;
					return true;
				}
				one_time=true;
			}

			//
			// Refresh rate switching
			//
			local r = calculate_refresh();
			set_game_refresh = r ? true : false;
			if ( set_game_refresh )
				run_cmd( r.tostring() );

			break;

		case Transition.FromGame:
			if ( blank_screen )
				blank_screen.visible=false;

			if ( set_game_refresh )
				run_cmd( default_hz.tostring() );

			set_game_refresh=false;
			break;

		case Transition.ToNewList:
			if ( do_audit )
				audit();
			break;
		}

		return false;
	}

	function audit()
	{
		print("LCDRefresh GAME AUDIT (" + fe.list.name + "/"
			+ fe.filters[fe.list.filter_index].name + ")\n");

		for (local i=0; i<fe.list.size; i++ )
		{
			local s = fe.game_info( Info.DisplayRefresh, i );
			local sf = s.tofloat();
			local cal = calculate_refresh( i );
			if ( cal && (( sf < min_hz ) || ( sf > max_hz )))
			{
				if (( cal == vector_hz )
						&& ( fe.game_info( Info.DisplayType, i ) == "vector" ))
					continue;

				local adjust = cal/sf + 0.0049;
				local adjust_str = "";
				if (( adjust < 1.5 ) && ( adjust > 0.5 ))
					adjust_str = " (speed " + format( "%.2f", adjust ) + ")";

				print( "\t" + format("%10s", fe.game_info( Info.Name, i )) + ": "
					+ sf + " Hz -> "
					+ cal.tostring() + " Hz" + adjust_str + "\n" );
			}
		}
	}
}

fe.plugin[ "LCDRefresh" ] <- LCDRefresh();
