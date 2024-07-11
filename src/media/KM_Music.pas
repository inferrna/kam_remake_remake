unit KM_Music;
{$I KaM_Remake.inc}
interface

//We have two choices for music libraries:
//BASS: Free for non-commercial projects. Requires bass.dll. Website: http://www.un4seen.com/
//ZLibPlay: GNU GPL license. Requires libzplay.dll. Website: http://libzplay.sourceforge.net/

//Comparison: - BASS's DLL is much smaller (102kb vs 2.13mb(!)) and BASS seems faster at loading tracks.
//            - ZLibPlay supports more formats, (FLAC, AC-3, AAC, PCM) but we don't care
//            - ZLibPlay is GPL but BASS is not, and BASS can only be used for free in non-commercial products

{$IFNDEF NO_MUSIC}
//  {$DEFINE USEBASS}
//  {$IFDEF MSWindows}
//    {.$DEFINE USELIBZPLAY}
//  {$ENDIF}
  {$DEFINE USESDL_MIXER}
{$ENDIF}

uses
  Types
  {$IFDEF USEBASS}     , Bass {$ENDIF}
  {$IFDEF USESDL_MIXER}, SDL2, SDL2_mixer {$ENDIF}
  {$IFDEF USELIBZPLAY} , libZPlay {$ENDIF}
  ;

type
  // We have two kinds of playable music:
  // Track/Song - song we are playing now from the list
  // Other/Briefing - voice file we play for campaign briefing
  //todo: Would be nice to choose just 2 terms and stick to them
  TKMMusicLib = class
  private type
    TKMFadeState = (fsNone, fsFadeOut, fsFadeIn, fsFaded);
  private
    fCount: Integer;
    fIndex: Integer; //Points to the index in TrackOrder of the current track
    fTracks: TStringDynArray;
    fTrackOrder: TIntegerDynArray; //Each index points to an index of MusicTracks
    //MIDICount,MIDIIndex:integer;
    //MIDITracks: array[1..256]of string;
    fIsInitialized: Boolean;
    fEnabled: Boolean;
    fPrevVolume: Single; // Volume before mute
    fVolume: Single;
    {$IFDEF USEBASS} fBassStreams: array[0..1] of Cardinal; {$ENDIF}
    {$IFDEF USESDL_MIXER}SDLStreams: array[0..1] of PMix_Music; {$ENDIF}
    {$IFDEF USELIBZPLAY} ZPlayers: array[0..1] of ZPlay; {$ENDIF} //I dislike that it's not TZPlay... Guess they don't know Delphi conventions.
    fFadeState: TKMFadeState;
    fFadeStarted: Cardinal;
    fFadeTime: Integer;
    fToPlayAfterFade: UnicodeString;
    fFadedToPlayOther: Boolean;
    fOtherVolume: Single;
    procedure PlayFile(const FileName: UnicodeString; iStreamId: Integer);
    procedure ScanTracks(const aPath: UnicodeString);
    procedure ShuffleSongs; //should not be seen outside of this class
    procedure UnshuffleSongs;
    procedure SetMuted(const aMuted: Boolean);
    function GetMuted: Boolean;
    function GetPrevVolume: Single;

    property PrevVolume: Single read GetPrevVolume write fPrevVolume;
  public
    constructor Create(aVolume: Single);
    destructor Destroy; override;

    property Muted: Boolean read GetMuted write SetMuted;
    procedure SetPlayerVolume(aValue: Single; iStreamId: Integer);

    procedure PlayMenuTrack;
    procedure PlayNextTrack;
    procedure PlayPreviousTrack;
    function IsEnded(iStreamId: Integer): Boolean;
    procedure Pause;
    procedure Resume;
    procedure Stop(iStreamId: Integer);
    procedure ToggleMuted;
    procedure ToggleEnabled(aEnableMusic: Boolean);
    procedure ToggleShuffle(aEnableShuffle: Boolean);
    procedure Fade; overload;
    procedure Fade(aFadeTime: Integer); overload;
    procedure SetVolume(aValue: Single; iStreamId: Integer);
    function  GetVolume(iStreamId: Integer): Single;
    procedure UnfadeStarting;
    procedure Unfade; overload;
    procedure Unfade(aFadeTime: Integer; aHandleCrackling: Boolean = False); overload;
    procedure PauseToPlayFile(const aFileName: UnicodeString; aVolume: Single);
    function GetTrackTitle: UnicodeString;
    procedure UpdateStateIdle; //Used for fading
  end;


var
  gMusic: TKMMusicLib;


implementation
uses
  SysUtils, KromUtils, Math,
  KM_Defaults,
  KM_Log, KM_CommonUtils;


const
  STARTING_MUSIC_UNFADE_TIME = 500; //Time to unfade game starting music, in ms
  FADE_TIME = 2000; //Time that a fade takes to occur in ms


{ TKMMusicLib }
constructor TKMMusicLib.Create(aVolume: Single);
var
  I: Integer;
begin
  inherited Create;
  fIsInitialized := True;
  fEnabled := True;

  if not DirectoryExists(ExeDir + 'Music') then
    ForceDirectories(ExeDir + 'Music');

  ScanTracks(ExeDir + 'Music' + PathDelim);


  {$IFDEF USELIBZPLAY}
  ZPlayers[0] := ZPlay.Create; //Note: They should have used TZPlay not ZPlay for a class
  ZPlayers[1] := ZPlay.Create;
  {$ENDIF}
  {$IFDEF USESDL_MIXER}
  if (SDL_Init(SDL_INIT_AUDIO) < 0) then
  begin
    gLog.AddTime('Failed to initialize SDL: '+SDL_GetError());
    fIsInitialized := False;
  end;
  if Mix_Init(MIX_INIT_MP3) <> MIX_INIT_MP3 then
  begin
    fIsInitialized := False;
  end;
  if (Mix_OpenAudio(44100, AUDIO_S16SYS, 2, 640) < 0) then
  begin
    gLog.AddTime('Failed to open audio device: ' + Mix_GetError());
    fIsInitialized := False;
    Mix_Quit();
    SDL_Quit();
  end;
  //SDLStream, SDLStreamOther: PMix_Music;
  {$ENDIF}

  {$IFDEF USEBASS}
  // Setup output - default device, 44100hz, stereo, 16 bits
  BASS_SetConfig(BASS_CONFIG_DEV_DEFAULT, 1);
  if not BASS_Init(-1, 44100, 0, 0, nil) then
  begin
    gLog.AddTime('Failed to initialize the music playback device');
    fIsInitialized := False;
  end;
  {$ENDIF}

  SetVolume(aVolume, 0);

  // Initialise TrackOrder
  for I := 0 to fCount - 1 do
    fTrackOrder[I] := I;

  gLog.AddTime('Music init done, ' + IntToStr(fCount) + ' tracks found');
end;


destructor TKMMusicLib.Destroy;
begin
  {$IFDEF USELIBZPLAY}
  ZPlayers[0].Free;
  ZPlayers[1].Free;
  {$ENDIF}
  {$IFDEF USESDL_MIXER}
  Mix_FreeMusic(SDLStreams[0]);
  Mix_FreeMusic(SDLStreams[1]);
  {$ENDIF}
  {$IFDEF USEBASS}
  BASS_Stop; //Stop all Bass output
  //Free the streams we may have used (will just return False if the stream is invalid)
  BASS_StreamFree(fBassStreams[0]);
  BASS_StreamFree(fBassStreams[1]);
  BASS_Free; //Frees this usage of BASS, allowing it to be recreated successfully
  {$ENDIF}

  inherited;
end;


procedure TKMMusicLib.PlayFile(const FileName: UnicodeString; iStreamId: Integer);
{$IFDEF USEBASS}
var
  errorCode: Integer;
{$ENDIF}
begin
  if not fIsInitialized then Exit;
  if fFadeState <> fsNone then Exit; //Don't start a new track while fading or faded

  //Cancel previous sound
  Stop(iStreamId);

  if not FileExists(FileName) then Exit; //Make it silent

  {$IFDEF USELIBZPLAY}
  if not ZPlayers[iStreamId].OpenFile(AnsiString(FileName), sfAutodetect) then //Detect file type automatically
    Exit; //File failed to load
  if not ZPlayers[iStreamId].StartPlayback then
    Exit; //Playback failed to start
  {$ENDIF}
  {$IFDEF USESDL_MIXER}
  SDLStreams[iStreamId] := Mix_LoadMUS(PChar(AnsiString(filename)));
  if SDLStreams[iStreamId] = nil then
  begin
     gLog.AddTime('Failed to load music '+filename+'! SDL_mixer Error: '+Mix_GetError());
     Exit;
  end;
  if Mix_PlayMusic(SDLStreams[iStreamId], 1) = -1 then
  begin
     gLog.AddTime('Failed to play music '+filename+'! SDL_mixer Error: '+Mix_GetError());
     Exit;
  end;
  {$ENDIF}
  {$IFDEF USEBASS}
  BASS_StreamFree(fBassStreams[iStreamId]); //Free the existing stream (will just return False if the stream is invalid)
  fBassStreams[iStreamId] := BASS_StreamCreateFile(FALSE, PChar(FileName), 0, 0, BASS_STREAM_AUTOFREE {$IFDEF UNICODE} or BASS_UNICODE{$ENDIF});

  BASS_ChannelPlay(fBassStreams[iStreamId], True); //Start playback from the beggining

  errorCode := BASS_ErrorGetCode;
  if errorCode <> BASS_OK then Exit; //Error
  {$ENDIF}

  SetVolume(fVolume, iStreamId); //Need to reset music volume after starting playback
end;


{Update music gain (global volume for all sounds/music)}
procedure TKMMusicLib.SetVolume(aValue: Single; iStreamId: Integer);
begin
  if not fIsInitialized then Exit; //Keep silent
  if not fEnabled then Exit;

  fVolume := aValue;

  if fVolume > 0 then
    fPrevVolume := fVolume;

  SetPlayerVolume(fVolume, iStreamId);
end;


// Set player volume (game music volume stays unchanged)
procedure TKMMusicLib.SetPlayerVolume(aValue: Single; iStreamId: Integer);
begin
  {$IFDEF USELIBZPLAY}
  ZPlayers[iStreamId].SetPlayerVolume(Round(aValue * 100), Round(aValue * 100)); //0=silent, 100=max
  {$ENDIF}
  {$IFDEF USESDL_MIXER}
  Mix_Volume(iStreamId, Round(aValue * MIX_MAX_VOLUME));
  {$ENDIF}
  {$IFDEF USEBASS}
  BASS_ChannelSetAttribute(fBassStreams[iStreamId], BASS_ATTRIB_VOL, aValue); //0=silent, 1=max
  {$ENDIF}
end;


function TKMMusicLib.GetVolume(iStreamId: Integer): Single;
{$IFDEF USELIBZPLAY}
var
  LeftVolume, RightVolume: Integer;
{$ENDIF}
begin
  {$IFDEF USELIBZPLAY}
  ZPlayers[iStreamId].GetPlayerVolume(LeftVolume, RightVolume); //0=silent, 100=max
  Result := (LeftVolume + RightVolume) / 200;
  {$ENDIF}
  {$IFDEF USESDL_MIXER}
  Result := Single(Mix_Volume(iStreamId, -1)) / MIX_MAX_VOLUME;
  {$ENDIF}
  {$IFDEF USEBASS}
  BASS_ChannelGetAttribute(fBassStreams[iStreamId], BASS_ATTRIB_VOL, Result);
  {$ENDIF}
end;


procedure TKMMusicLib.ScanTracks(const aPath: UnicodeString);
var
  searchRec: TSearchRec;
begin
  if not fIsInitialized then Exit;
  fCount := 0;
  if not DirectoryExists(aPath) then Exit;

  SetLength(fTracks, 255);

  FindFirst(aPath + '*.*', faAnyFile - faDirectory, searchRec);
  try
    repeat
      if (GetFileExt(searchRec.Name) = 'MP3') //Allow all formats supported by both libraries
      or (GetFileExt(searchRec.Name) = 'MP2')
      or (GetFileExt(searchRec.Name) = 'MP1')
      or (GetFileExt(searchRec.Name) = 'WAV')
      or (GetFileExt(searchRec.Name) = 'OGG')
      {$IFDEF USEBASS} //Formats supported by BASS but not LibZPlay
      or (GetFileExt(SearchRec.Name) = 'AIFF')
      {$ENDIF}
      {$IFDEF USESDL_MIXER}
      //or (GetFileExt(SearchRec.Name) = 'MIDI' //TODO: have to test if it works
      {$ENDIF}
      {$IFDEF USELIBZPLAY} //Formats supported by LibZPlay but not BASS
      or (GetFileExt(searchRec.Name) = 'FLAC')
      or (GetFileExt(searchRec.Name) = 'OGA')
      or (GetFileExt(searchRec.Name) = 'AC3')
      or (GetFileExt(searchRec.Name) = 'AAC')
      {$ENDIF}
      then
      begin
        Inc(fCount);
        if fCount > Length(fTracks) then
          SetLength(fTracks, Length(fTracks) + 32);

        fTracks[fCount - 1] := aPath + searchRec.Name;
      end;
      {if GetFileExt(SearchRec.Name)='MID' then
      begin
        Inc(MIDICount);
        MIDITracks[MIDICount] := Path + SearchRec.Name;
      end;}
    until (FindNext(searchRec) <> 0);
  finally
    FindClose(searchRec);
  end;

  //Cut to length
  SetLength(fTracks, fCount);
  SetLength(fTrackOrder, fCount);

  fIndex := -1;
end;


procedure TKMMusicLib.PlayMenuTrack;
var
  prevVolume: Single;
begin
  if not fIsInitialized then Exit;
  if fCount = 0 then Exit; //no music files found
  if fIndex = 0 then Exit; //It's already playing
  fIndex := 0;
  // There was audio crackling after loading screen, here we fix it by setting a delay and fading the volume.
  prevVolume := fVolume;
  fVolume := 0;
  PlayFile(fTracks[0], 0);
  fVolume := prevVolume;
  UnfadeStarting;
end;


procedure TKMMusicLib.PlayNextTrack;
begin
  if not fIsInitialized then Exit;
  if fCount = 0 then Exit; //no music files found
  if fFadeState <> fsNone then Exit;

  //Set next index, looped or random
  fIndex := (fIndex + 1) mod fCount;
  PlayFile(fTracks[fTrackOrder[fIndex]], 0);
end;


procedure TKMMusicLib.PlayPreviousTrack;
begin
  if not fIsInitialized then Exit;
  if fCount = 0 then Exit; //no music files found
  if fFadeState <> fsNone then Exit;

  fIndex := (fIndex + fCount - 1) mod fCount;
  PlayFile(fTracks[fTrackOrder[fIndex]], 0);
end;


//Check if Music is not playing, to know when new mp3 should be feeded
function TKMMusicLib.IsEnded(iStreamId: Integer): Boolean;
{$IFDEF USELIBZPLAY}
var
  status: TStreamStatus;
{$ENDIF}
begin
  {$IFDEF USELIBZPLAY} ZPlayers[iStreamId].GetStatus(status); {$ENDIF}
  Result := fIsInitialized
            {$IFDEF USELIBZPLAY}
            and (not status.fPlay and not status.fPause) //Not playing and not paused due to fade
            {$ENDIF}
            {$IFDEF USESDL_MIXER}
            and (Mix_Playing(iStreamId) <> 0);
            {$ENDIF}
            {$IFDEF USEBASS}
            and (BASS_ChannelIsActive(fBassStreams[iStreamId]) = BASS_ACTIVE_STOPPED)
            {$ENDIF}
            ;
end;



procedure TKMMusicLib.Stop(iStreamId: Integer);
begin
  if (Self = nil) or not fIsInitialized then Exit;
  {$IFDEF USELIBZPLAY} ZPlayers[iStreamId].StopPlayback; {$ENDIF}
  {$IFDEF USESDL_MIXER}
  if Mix_HaltChannel(iStreamId) = -1 then
     gLog.AddTime('Failed to halt channel '+iStreamId.toString+'! SDL_mixer Error: '+Mix_GetError());
  {$ENDIF}
  {$IFDEF USEBASS} BASS_ChannelStop(fBassStreams[iStreamId]); {$ENDIF}
  fIndex := -1;
end;


procedure TKMMusicLib.ToggleEnabled(aEnableMusic: Boolean);
begin
  fEnabled := aEnableMusic;
  if aEnableMusic then
    PlayMenuTrack //Start with the default track
  else
    Stop(0);
end;


function TKMMusicLib.GetMuted: Boolean;
begin
  Result := (fVolume = 0);
end;


function TKMMusicLib.GetPrevVolume: Single;
begin
  Result := IfThen(fPrevVolume = 0, 0.5, fPrevVolume);
end;


procedure TKMMusicLib.SetMuted(const aMuted: Boolean);
begin
  if Muted = aMuted then Exit;  // Nothing to change, just exit to avoid fPrevVolume overwrite

  if aMuted then
  begin
    fPrevVolume := fVolume;
    SetVolume(0, 0);
  end
  else
  begin
    SetVolume(PrevVolume, 0);
    fPrevVolume := 0;
  end;
end;


procedure TKMMusicLib.ToggleMuted;
begin
  SetMuted(not GetMuted);
end;


procedure TKMMusicLib.ToggleShuffle(aEnableShuffle: Boolean);
begin
  if aEnableShuffle then
    ShuffleSongs
  else
    UnshuffleSongs;
end;


procedure TKMMusicLib.ShuffleSongs;
var
  I, R, curSong: Integer;
begin
  if fIndex = -1 then Exit; // Music is disabled

  // Stay on the current song
  curSong := fTrackOrder[fIndex];

  // Shuffle everything except for first (menu) track
  for I := fCount - 1 downto 1 do
  begin
    R := RandomRange(1, I);
    KromUtils.SwapInt(fTrackOrder[R], fTrackOrder[I]);
    if fTrackOrder[I] = curSong then
      fIndex := I;
  end;
end;


procedure TKMMusicLib.UnshuffleSongs;
var
  I: Integer;
begin
  if fIndex = -1 then Exit; // Music is disabled
  fIndex := fTrackOrder[fIndex];

  //Reset every index of the TrackOrder array
  for I := 0 to fCount - 1 do
    fTrackOrder[I] := I;
end;


procedure TKMMusicLib.Fade;
begin
  Fade(FADE_TIME);
end;


procedure TKMMusicLib.Fade(aFadeTime: Integer);
{$IFDEF USELIBZPLAY}
var
  startTime, endTime: TStreamTime;
  left, right: Integer;
{$ENDIF}
begin
  if (not fIsInitialized) then Exit;
  fFadeTime := aFadeTime;
  fFadeState := fsFadeOut; //Fade it out
  fFadeStarted := TimeGet;
  {$IFDEF USELIBZPLAY}
  ZPlayers[0].GetPosition(startTime);
  endTime.ms := startTime.ms + aFadeTime;
  ZPlayers[0].GetPlayerVolume(left, right); //Start fade from the current volume
  ZPlayers[0].SlideVolume(tfMillisecond, startTime, left, right, tfMillisecond, endTime, 0, 0);
  {$ENDIF}
  {$IFDEF USESDL_MIXER}
  Mix_FadeOutChannel(0, aFadeTime);
  {$ENDIF}
  {$IFDEF USEBASS}
  BASS_ChannelSlideAttribute(fBassStreams[0], BASS_ATTRIB_VOL, 0, aFadeTime);
  {$ENDIF}
end;


procedure TKMMusicLib.UnfadeStarting;
begin
  Unfade(STARTING_MUSIC_UNFADE_TIME, True);
end;


procedure TKMMusicLib.Unfade;
begin
  Unfade(FADE_TIME);
end;


// aHandleCrackling flag is used to mitigate initial sound crackling
procedure TKMMusicLib.Unfade(aFadeTime: Integer; aHandleCrackling: Boolean = False);
{$IFDEF USELIBZPLAY}
var
  startTime, endTime: TStreamTime;
  left, right: Integer;
{$ENDIF}
begin
  if (not fIsInitialized) then Exit;
  fFadeTime := aFadeTime;
  fFadeState := fsFadeIn; //Fade it in
  fFadeStarted := TimeGet;
  {$IFDEF USELIBZPLAY}
  //LibZPlay has a nice SlideVolume function we can use
  ZPlayers[0].ResumePlayback; //Music may have been paused due to fade out
  if aHandleCrackling then Sleep(25);
  ZPlayers[0].GetPosition(startTime);
  endTime.ms := startTime.ms + aFadeTime;
  ZPlayers[0].GetPlayerVolume(left, right); //Start fade from the current volume
  ZPlayers[0].SlideVolume(tfMillisecond, startTime, left, right, tfMillisecond, endTime, Round(fVolume * 100), Round(fVolume * 100));
  {$ENDIF}
  {$IFDEF USESDL_MIXER}
  Mix_FadeInMusic(SDLStreams[0], -1, aFadeTime);  //TODO possible wrong loop count
  {$ENDIF}
  {$IFDEF USEBASS}
  BASS_ChannelPlay(fBassStreams[0], False); //Music may have been paused due to fade out
  if aHandleCrackling then Sleep(25);
  BASS_ChannelSlideAttribute(fBassStreams[0], BASS_ATTRIB_VOL, fVolume, aFadeTime);
  {$ENDIF}
end;


procedure TKMMusicLib.UpdateStateIdle;
begin
  if not fIsInitialized then Exit;

  case fFadeState of
    fsFadeIn:   if TimeSince(fFadeStarted) > fFadeTime then
                  fFadeState := fsNone;
    fsFadeOut:  begin
                  if TimeSince(fFadeStarted) > fFadeTime then
                  begin
                    fFadeState := fsFaded;
                    {$IFDEF USELIBZPLAY} ZPlayers[0].PausePlayback; {$ENDIF}
                    {$IFDEF USESDL_MIXER}
                    Mix_Pause(0);
                    {$ENDIF}
                    {$IFDEF USEBASS} BASS_ChannelPause(fBassStreams[0]); {$ENDIF}
                  end
                  else
                  //Start playback of other file half way through the fade
                  if (TimeSince(fFadeStarted) > fFadeTime div 2)
                    and (fToPlayAfterFade <> '') then
                  begin
                    fFadedToPlayOther := True;
                    PlayFile(fToPlayAfterFade, 1);
                    fToPlayAfterFade := '';
                  end;
                end;
  end;

  if fFadedToPlayOther and (fFadeState = fsFaded) and IsEnded(1) then
  begin
    fFadedToPlayOther := False;
    Unfade;
  end;
end;


procedure TKMMusicLib.Pause;
begin
  if not fIsInitialized then Exit;

  {$IFDEF USELIBZPLAY} ZPlayers[0].PausePlayback; {$ENDIF}
  {$IFDEF USESDL_MIXER}
  Mix_Pause(0);
  {$ENDIF}
  {$IFDEF USEBASS} BASS_ChannelPause(fBassStreams[0]); {$ENDIF}
end;


procedure TKMMusicLib.Resume;
begin
  if not fIsInitialized then Exit;

  {$IFDEF USELIBZPLAY} ZPlayers[0].ResumePlayback; {$ENDIF}
  {$IFDEF USESDL_MIXER}
  Mix_Resume(0);
  {$ENDIF}
  {$IFDEF USEBASS} BASS_ChannelPlay(fBassStreams[0], False); {$ENDIF}
end;


procedure TKMMusicLib.PauseToPlayFile(const aFileName: UnicodeString; aVolume: single);
begin
  fOtherVolume := aVolume;
  if fFadeState in [fsNone, fsFadeIn] then
  begin
    Fade;
    fToPlayAfterFade := aFilename
  end
  else
    if (fFadeState = fsFaded) or ((fFadeState = fsFadeOut) and fFadedToPlayOther) then
    begin
      fFadedToPlayOther := True;
      PlayFile(aFilename, 1) //Switch playback immediately
    end
    else
      fToPlayAfterFade := aFilename; //We're still in the process of fading out, the file hasn't started yet
end;


function TKMMusicLib.GetTrackTitle: UnicodeString;
begin
  if not fIsInitialized then Exit;
  if not InRange(fIndex, Low(fTracks), High(fTracks)) then Exit;

  Result := TruncateExt(ExtractFileName(fTracks[fTrackOrder[fIndex]]));
end;

end.
