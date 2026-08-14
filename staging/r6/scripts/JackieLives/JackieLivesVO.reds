// =============================================================================
//  JackieLives — native voice-over shim
//
//  Makes an entity speak ONE SPECIFIC line of the game's own voice-over, chosen
//  by its String ID, with no audio shipped and no Audioware.
//
//  This file exists only because CET's Lua cannot do two things:
//    1. hold a 19-digit String ID exactly (Lua numbers are doubles — they lose
//       precision above 2^53, and every ID here is ~2e18), and
//    2. reliably build the nested `audioDialogLineEventData` struct that
//       `DialogLineEvent` carries.
//  So Lua passes the ID as a STRING and this file parses it with StringToUint64.
//
//  Everything else — when to speak, what the subtitle says, how long it stays,
//  pacing, cooldowns — stays in Lua where the content lives. Keep it that way:
//  this file should stay small enough to audit at a glance, because a redscript
//  compile error takes down EVERY redscript mod the player has, not just ours.
//
//  Technique credit: V Voice Framework (Nexus 30646), r6/scripts/Johnny Voice
//  Framework.reds:109-133. See docs/research/native_vo_dialogline.md.
//
//  NAMING: every symbol is prefixed JLVO_ / JLVO. NCLives ships the same shim
//  under NCLVO_ so both mods can be installed together — redscript would refuse
//  to compile two definitions of the same name. Never drop the prefix.
// =============================================================================

// -----------------------------------------------------------------------------
//  Restores an entity's own voice tag after we borrowed someone else's.
//  Only used when the caller asks for a tag swap (see JLVO_PlayLineAs).
// -----------------------------------------------------------------------------
public class JLVOTagRestore extends DelayCallback {
  private let m_obj: wref<GameObject>;
  private let m_tag: CName;

  public static func Create(obj: ref<GameObject>, tag: CName) -> ref<JLVOTagRestore> {
    let cb = new JLVOTagRestore();
    cb.m_obj = obj;
    cb.m_tag = tag;
    return cb;
  }

  public func Call() -> Void {
    if !IsDefined(this.m_obj) { return; }
    let evt = new entInjectVoiceTagEvent();
    evt.voiceTagName = this.m_tag;
    this.m_obj.QueueEvent(evt);
  }
}

// -----------------------------------------------------------------------------
//  Presence probe. Lua calls this inside a pcall: if it returns a number, the
//  shim is installed and the native path is available. Bump the number when the
//  signature of anything below changes, so an old .reds next to a new .lua is
//  detected rather than silently misbehaving.
// -----------------------------------------------------------------------------
@addMethod(GameObject)
public final func JLVO_Version() -> Int32 {
  return 3;
}

// -----------------------------------------------------------------------------
//  v3 — V SPEAKS. (Ported from NCLives' NCLVO_SpeakAsPlayerVariant, v1.71.)
//
//  Everything above this puts a line in JACKIE's mouth. This one puts a line in
//  V's, so the player's own dialogue choices can be heard instead of read. It is
//  a SEPARATE entry point rather than a flag on JLVO_Speak for one reason: that
//  function can inject someone else's voice tag, and doing that to the player is
//  the one mistake available here — V would answer Jackie in Jackie's voice. This
//  signature cannot express it. There is no tag argument and there never will be;
//  the only tag it may inject is V's own.
//
//  `variant` picks the SHAPE of the event, because a line's male and female takes
//  share ONE String ID and the ENGINE chooses between them — a mod cannot name the
//  take it wants, it can only change the question:
//      0  isPlayer = true,  no tag injected     (the evidenced default)
//      1  isPlayer = false, inject V's tag      (how V Voice Framework speaks)
//      2  isPlayer = true,  inject V's tag
//  jlPlayerVariant() in init.lua selects it, driven by the Esc-menu control
//  (Jackie Lives > Voice > "V's voice") and persisted to jl_settings.txt, so a
//  player whose V sounds like the wrong gender fixes it without a redeploy.
// -----------------------------------------------------------------------------
@addMethod(GameObject)
public final func JLVO_SpeakAsPlayer(idDec: String, ctx: Int32, expr: Int32,
                                     variant: Int32, dur: Float) -> Bool {
  let ruid: Uint64 = StringToUint64(idDec, 0ul);
  if Equals(ruid, 0ul) { return false; }

  if variant == 1 || variant == 2 {
    let inj = new entInjectVoiceTagEvent();
    inj.voiceTagName = n"v";
    this.QueueEvent(inj);
  }

  let ctxEnum: locVoiceoverContext = locVoiceoverContext.Vo_Context_Combat;
  if ctx >= 0 { ctxEnum = IntEnum<locVoiceoverContext>(ctx); }

  let data: audioDialogLineEventData;
  data.stringId   = HashToCRUID(ruid);
  data.isPlayer   = variant != 1;
  data.isHolocall = false;
  data.context    = ctxEnum;
  if expr >= 0 { data.expression = IntEnum<locVoiceoverExpression>(expr); }

  let evt = new DialogLineEvent();
  evt.data = data;
  this.QueueEvent(evt);

  // Put V's own tag back afterwards even though V's tag is what we injected: an
  // inject is a rebind, and leaving one live past the line is how an entity ends
  // up speaking as somebody else for the rest of the session.
  if variant == 1 || variant == 2 {
    let after: Float = dur;
    if after < 0.5 { after = 0.5; }
    GameInstance.GetDelaySystem(this.GetGame())
      .DelayCallback(JLVOTagRestore.Create(this, n"v"), after + 0.4, true);
  }
  return true;
}

// -----------------------------------------------------------------------------
//  v2 — the one entry point. Supersedes JLVO_PlayLine / JLVO_PlayLineAs, which
//  are kept below so a stale .reds next to a new .lua still speaks.
//
//  Adds `expr` (locVoiceoverExpression), which v1 never set and which decides
//  HOW the line is placed in the world rather than which line plays:
//
//      0  Vo_Expression_Spoken        <- an NPC talking in front of you
//      1  Vo_Expression_Phone            a call: deliberately in your head
//      2  Vo_Expression_InnerDialog      Johnny-style, no world position
//      3  Vo_Expression_Loudspeaker_Room
//      6  Vo_Expression_Radio
//     11  Vo_Expression_Helmet
//
//  and `ctx` (locVoiceoverContext), verified numbers:
//      0  Vo_Context_Quest           <- conversation. What our dialogue IS.
//      1  Vo_Context_Community
//      2  Vo_Context_Combat             what V Voice Framework used, because its
//                                       lines are combat barks
//      3  Vo_Context_Minor_Activity
//      5  Default_Vo_Context
//
//  Both are Int32 rather than enum members ON PURPOSE — naming a member that
//  doesn't exist is a compile error, and that breaks every redscript mod the
//  player has. Only Vo_Context_Combat is named anywhere in this file.
// -----------------------------------------------------------------------------
@addMethod(GameObject)
public final func JLVO_Speak(idDec: String, ctx: Int32, expr: Int32,
                             voiceTag: CName, restoreTag: CName, dur: Float) -> Bool {
  let ruid: Uint64 = StringToUint64(idDec, 0ul);
  if Equals(ruid, 0ul) { return false; }

  if NotEquals(voiceTag, n"") {
    let inj = new entInjectVoiceTagEvent();
    inj.voiceTagName = voiceTag;
    this.QueueEvent(inj);
  }

  let ctxEnum: locVoiceoverContext = locVoiceoverContext.Vo_Context_Combat;
  if ctx >= 0 { ctxEnum = IntEnum<locVoiceoverContext>(ctx); }

  let data: audioDialogLineEventData;
  data.stringId   = HashToCRUID(ruid);
  data.isPlayer   = false;
  data.isHolocall = false;
  data.context    = ctxEnum;
  if expr >= 0 { data.expression = IntEnum<locVoiceoverExpression>(expr); }

  let evt = new DialogLineEvent();
  evt.data = data;
  this.QueueEvent(evt);

  if NotEquals(voiceTag, n"") && NotEquals(restoreTag, n"") {
    let after: Float = dur;
    if after < 0.5 { after = 0.5; }
    GameInstance.GetDelaySystem(this.GetGame())
      .DelayCallback(JLVOTagRestore.Create(this, restoreTag), after + 0.4, true);
  }
  return true;
}

// -----------------------------------------------------------------------------
//  Speak line `idDec` (the String ID in DECIMAL, as a string) from THIS entity.
//
//  idDec  e.g. "1660220866564214792" — the trailing hex of the line's .wem stem
//         in decimal, which is exactly what our content already stores as
//         `sfx = "jl_1660220866564214792"` and what SoundDB calls the line id.
//  ctx    a locVoiceoverContext as an Int32, or -1 for the default. Passed as an
//         int on purpose: naming an enum member that doesn't exist is a COMPILE
//         error, and a compile error here breaks every redscript mod installed.
//         Vo_Context_Combat is the only member named in this file because it is
//         the only one verified against a shipped mod. Other contexts are
//         reachable by number without risking the build.
//
//  Returns false only if the ID could not be parsed. A well-formed ID that the
//  game doesn't know is silent, not an error — which is the failure mode we
//  want: one missing line, not a dead mod. (Compare Audioware, where a single
//  missing .wav made it drop the entire bank.)
// -----------------------------------------------------------------------------
@addMethod(GameObject)
public final func JLVO_PlayLine(idDec: String, ctx: Int32) -> Bool {
  let ruid: Uint64 = StringToUint64(idDec, 0ul);
  if Equals(ruid, 0ul) { return false; }

  let ctxEnum: locVoiceoverContext = locVoiceoverContext.Vo_Context_Combat;
  if ctx >= 0 {
    ctxEnum = IntEnum<locVoiceoverContext>(ctx);
  }

  let data: audioDialogLineEventData;
  data.stringId = HashToCRUID(ruid);
  data.isPlayer = false;
  data.context  = ctxEnum;

  let evt = new DialogLineEvent();
  evt.data = data;
  this.QueueEvent(evt);
  return true;
}

// -----------------------------------------------------------------------------
//  Same, but speak in SOMEONE ELSE'S voice: temporarily rebind which voice bank
//  this entity draws from, then restore `restoreTag` after `dur` seconds.
//
//  We do not need this for Jackie — he is a real Jackie entity and already
//  carries his own voice tag — but it is what lets any body speak any
//  character's lines (V Voice Framework plays Johnny out of V's body this way),
//  and NCLives needs exactly that for personas voiced by someone else.
//
//  ⚠️ The restore is a timed callback, not a completion signal: the game gives
//  us no "line finished" event. If `dur` is wrong the tag comes back early or
//  late, so pass a real duration (vo_durations.lua) and not a guess.
// -----------------------------------------------------------------------------
@addMethod(GameObject)
public final func JLVO_PlayLineAs(idDec: String, ctx: Int32, voiceTag: CName, restoreTag: CName, dur: Float) -> Bool {
  if NotEquals(voiceTag, n"") {
    let inj = new entInjectVoiceTagEvent();
    inj.voiceTagName = voiceTag;
    this.QueueEvent(inj);
  }

  let played: Bool = this.JLVO_PlayLine(idDec, ctx);

  if NotEquals(voiceTag, n"") && NotEquals(restoreTag, n"") {
    let after: Float = dur;
    if after < 0.5 { after = 0.5; }
    GameInstance.GetDelaySystem(this.GetGame())
      .DelayCallback(JLVOTagRestore.Create(this, restoreTag), after + 0.4, true);
  }
  return played;
}
