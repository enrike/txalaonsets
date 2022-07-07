/* Txalaparta onset detection. It expects a contact mic per plank (taula) and stick (makila). To be used with a 8 input sound card. The piano roll window requires the TxalaScoreGUI class.

The record button records a mono audio file of the selected audio input and a CVS text file with the onset event information. The CVS format is "timestamp, amplitude, plank, player\n";

Change parameters in the variables

channel usage for a 8 input setup:

1 plank MIC IN to mono record the audio
2 plank 1
3 plank 2
4 plank 3
5 player A left hand.  5AL
6 player A right hand. 6AR
7 player B left hand   7BL
8 player B right hand  7BR

AUDIO onset events format -> number, /onset, msgID, trigger, time, onsetflags (7 channels, 3 planks + 4 sticks), amps (7 channels, 3 planks + 4 sticks here we are only interested in the planks)

e.g
[ /onset, 1002, -1, 3.4973542690277, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.00069872301537544, 0.0080843009054661, 0.00015763912233524, 9.7239491879009e-05, 6.7167900851928e-05, 0.00033587866346352, 0.0027722415979952 ]
*/

(// just to test inputs
o = Server.default.options;
o.numInputBusChannels = 8;
o.numOutputBusChannels = 8;
s.waitForBoot{	s.meter(8,8) }
)



( // run this
var onsetchannels = [1,2,3,4,5,6,7]; // input channels to check for onsets. skip 0. use that to record audio
var input = 8; // input channel to record audio from
var onsetthr = 0.05; // audio onset threshold
var relaxt = 0.005; // audio onset fall time
var gain = 10; // if signal too weak. gain for planks
var gain2 = 15; // separated gain for sticks
var odftype = \wphase; //both \mk1 and \wphase work best
var prevtime = 0; // store the previous hit's time to avoid duplicated events
var recpath = Platform.recordingsDir; // will save there audio and cvs file
var data = "";
var filename = "";
var newhitF = {}; // used by piano rol
var hitcount = 0;
var incomplete = 0;

o = Server.default.options;
o.numInputBusChannels = 8;
o.numOutputBusChannels = 8;

try{w.close; t.close};

s.waitForBoot{
	SynthDef(\onsets, {|gain=1, gain2=1, threshold=0.1, relaxtime=0.05, odftype=\mk1, t_trig=1|
		var onsets, signals, levels, fft;
		signals = SoundIn.ar(onsetchannels) * [gain, gain, gain, gain2, gain2, gain2, gain2]; // skip channel 0 !!!
		levels = WAmp.kr(signals, 0.04);
		fft = FFT(Array.fill(signals.size, { LocalBuf(1024) }), signals, wintype:1);
		onsets = Onsets.kr(fft, threshold, odftype:odftype, relaxtime:relaxtime, floor:0.1,
			mingap:1, medianspan:11, whtype:1, rawodf:0);
		SendReply.kr(onsets, '/onset', [Sweep.ar(t_trig).asArray++onsets++levels] );
	}).add;

	Server.default.sync;

	p.free;
	r.free;
	r = Recorder.new(Server.default);
	r.recHeaderFormat = "wav";

	s.meter(8,8);

	p = Synth(\onsets, [\odftype, odftype]);

	Server.default.sync;

	w = Window.new("onset detection values", Rect(100, 100, 355, 190)).front;
	w.view.decorator = FlowLayout(w.view.bounds);
	w.view.decorator.gap=2@2;
	EZSlider( w,         // parent
		350@30,    // bounds
		"plank gain",  // label
		ControlSpec(1, 20, \lin, 0.01, 1),     // controlSpec
		{ |ez| p.set(\gain, ez.value) }, // action
		gain ,// initial value
		true
	).numberView.maxDecimals = 3 ;
		EZSlider( w,         // parent
		350@30,    // bounds
		"stick gain",  // label
		ControlSpec(1, 20, \lin, 0.01, 1),     // controlSpec
		{ |ez| p.set(\gain2, ez.value) }, // action
		gain2 ,// initial value
		true
	).numberView.maxDecimals = 3 ;
	EZSlider( w,         // parent
		350@30,    // bounds
		"thresh",  // label
		ControlSpec(0, 1, \lin, 0.01, 0.1),     // controlSpec
		{ |ez| p.set(\threshold, ez.value) }, // action
		onsetthr, // initial value
		true
	).numberView.maxDecimals = 3 ;
	EZSlider( w,
		350@30,
		"relaxt",
		\amp,
		{ |ez| p.set(\relaxtime, ez.value) },
		relaxt, // initial value
		true
	).numberView.maxDecimals = 3 ;
	Button(w, Rect(20, 20, 340, 25))
	.states_([
		["GO RECORD DATA", Color.white, Color.black],
		["RECORDING...", Color.black, Color.red]
	])
	.action_({ arg butt;
		if (butt.value.asBoolean, {
			s.waitForBoot({
				filename = "/txala_"++Date.getDate.stamp;
				data = "timestamp, amplitude, plank, player\n"; // reset
				r.prepareForRecord(recpath++filename++".wav", 1); // mono from channel 1
				p.set(\t_trig, 1); // reset Sweep to start counting
				{ r.record(bus:input) }.defer;
				("RECORDING TO"+recpath).postln;
			})
		}, {
			data.writeArchive(recpath ++ Platform.pathSeparator ++ filename ++".csv");
			try{ r.stopRecording };
		});
	});
	Button(w, Rect(20, 20, 340, 25))
	.states_([
		["Open piano roll", Color.white, Color.black]
	])
	.action_({ arg butt;
		//GUI WINDOW
		try{t.close};
		t = TxalaScoreGUI.new;
		t.doTxalaScore(width:1320, height:350); //width=1020, height=350, timeframe=4, numactiveplanks=1
		t.updateNumPlanks(3);

		newhitF = {|data|
			t.hit(SystemClock.seconds, data[\amp], data[\player], data[\plank], data[\stick]); // draw the new hit into the piano roll GUI
		};
	});


	// onsets from contact mics
	OSCdef(\txalaonsetOSCdef).clear;
	OSCdef(\txalaonsetOSCdef).free;
	OSCdef(\txalaonsetOSCdef, {|msg, time, addr, recvPort|
		var plank_onsets = msg[4..6]; // 3 planks
		var plank_amps = msg[11..13];
		var stick_onsets = msg[7..10]; // 4 sticks
		var hitdata = Dictionary[\time -> -1, \amp -> -1, \player-> -1, \channel-> -1, \stick-> -1]; // reset

		//msg.postln;

		hitdata[\time] = msg[3];

		if (hitdata[\time] > prevtime, { // avoid duplicates
			var player = 0;
			hitcount = hitcount + 1;
			hitcount.postln;

			["plank onsets", plank_onsets].postln;
			["sticks onsets", stick_onsets].postln;
			["plank amps", plank_amps].postln;

			if ((plank_onsets.sum > 0) && (stick_onsets.sum > 0), { // at least one onset in both

				if (stick_onsets.indexOf(1.0) > 1, { //0,1 playerA, 2,3 playerB
					hitdata[\player] = 1; // else 0
				});
				hitdata[\plank] = plank_onsets.indexOf(1.0);
				hitdata[\stick] = stick_onsets.indexOf(1.0);
				hitdata[\amp] = plank_amps[plank_onsets.indexOf(1.0)];

				//"--- HIT DATA ----".postln;
				["time", hitdata[\time]].postln;

				//["player", hitdata[\player]].postln;
				//["in plank",hitdata[\plank]].postln;
				//["with stick", hitdata[\stick]].postln;
				//["with amp", hitdata[\amp]].postln;

				//CVS "timestamp, amplitude, plank, player\n";
				data = data
				++ hitdata[\time] ++ ", "
				++ hitdata[\amp] ++ ", "
				++ hitdata[\plank] ++ ", "
				++ hitdata[\player] ++ "\n";

				newhitF.value(hitdata); // NOW DISPLAY IN PIANO ROLL AND CLEAR
			}, {
				incomplete = incomplete + 1;
				(">>> incomplete hit!!"+incomplete).postln
			});
		}, {"skipping double hit".postln});

		prevtime = hitdata[\time]; // store
	}, '/onset');

};
)





