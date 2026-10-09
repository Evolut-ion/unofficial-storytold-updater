; Copyright (c) 2026 OfficialEv0 - MIT License (see ..\LICENSE)
; Unofficial Storytold Updater - staged installer
; Build:  ..\build.ps1   (or ISCC.exe Storytold-Updater.iss)   ->  ..\dist\StorytoldUpdaterSetup.exe
#define AppName    "Unofficial Storytold Updater"
#ifndef AppVersion
  #define AppVersion "1.0.0"   ; CI overrides this with /DAppVersion=<tag>
#endif
#define PS         "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId={{6B1F6C7A-3C54-4E0B-9F77-5A0D6B0C51E2}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=OfficialEv0 (unofficial, not affiliated with Storytold)
DefaultDirName={autopf}\Storytold Updater
DefaultGroupName=Storytold
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=StorytoldUpdaterSetup
SetupIconFile=updater.ico
UninstallDisplayIcon={app}\updater.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
UsePreviousAppDir=yes

[Messages]
WelcomeLabel2=This will install [name/ver] and then let you choose which Storytold apps to install or update.%n%nThis is an unofficial, community-made tool and is not affiliated with or endorsed by Storytold or ArtCraft. The updater only installs official portable Windows x64 releases from github.com/storytold, and verifies every download against the release's SHA-256 checksums before installing it.

[Files]
Source: "..\StorytoldUpdater.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "updater.ico";             DestDir: "{app}"; Flags: ignoreversion
; the same script is also needed before install, to fetch the product list for the wizard
Source: "..\StorytoldUpdater.ps1"; DestDir: "{tmp}"; Flags: dontcopy

[Tasks]
Name: desktopicon;   Description: "Create a &desktop shortcut for the updater"
Name: startmenuicon; Description: "Create a &Start Menu shortcut for the updater"
Name: dailycheck;    Description: "&Check for updates every day at noon and install them silently (apps that are open are skipped)"; Flags: unchecked

[Icons]
Name: "{autodesktop}\Unofficial Storytold Updater"; Filename: "{#PS}"; Parameters: "{code:UpdaterArgs}"; WorkingDir: "{app}"; IconFilename: "{app}\updater.ico"; Tasks: desktopicon
Name: "{autoprograms}\Storytold\Unofficial Storytold Updater"; Filename: "{#PS}"; Parameters: "{code:UpdaterArgs}"; WorkingDir: "{app}"; IconFilename: "{app}\updater.ico"; Tasks: startmenuicon

[Run]
Filename: "schtasks.exe"; Parameters: "/Create /F /TN ""Storytold Updater"" /SC DAILY /ST 12:00 /TR ""{#PS} -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \""{app}\StorytoldUpdater.ps1\"" -Update -LogFile \""{localappdata}\StorytoldUpdater\auto.log\"""""; Flags: runhidden; Tasks: dailycheck
Filename: "{#PS}"; Parameters: "{code:UpdaterArgs}"; WorkingDir: "{app}"; Description: "Open {#AppName} now"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/Delete /F /TN ""Storytold Updater"""; Flags: runhidden; RunOnceId: "DelTask"

[Code]
const
  CONFIG_DIR = '{localappdata}\StorytoldUpdater';

{ keep the wizard responsive while the updater runs: drain the Windows message queue }
function PeekMessageW(var Msg: Byte; hWnd: Longint; Min, Max, Remove: LongWord): Boolean; external 'PeekMessageW@user32.dll stdcall';
function TranslateMessage(var Msg: Byte): Boolean; external 'TranslateMessage@user32.dll stdcall';
function DispatchMessageW(var Msg: Byte): Longint; external 'DispatchMessageW@user32.dll stdcall';

procedure PumpMessages;
var
  Msg: array[0..127] of Byte;   { MSG is 48 bytes on x64; oversize for safety }
begin
  while PeekMessageW(Msg[0], 0, 0, 0, 1 { PM_REMOVE }) do
  begin
    TranslateMessage(Msg[0]);
    DispatchMessageW(Msg[0]);
  end;
end;

var
  ProdPage: TWizardPage;
  ProdList: TNewCheckListBox;
  ProdDesc, ProdBusy: TNewStaticText;
  BtnAll, BtnUpd, BtnNone: TNewButton;
  OptPage: TInputDirWizardPage;
  ChkKeep, ChkExplorer, ChkStart: TNewCheckBox;
  ProdNames, ProdText: TStringList;
  ProdsLoaded: Boolean;

function UpdaterArgs(Param: String): String;
begin
  Result := '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
            ExpandConstant('{app}\StorytoldUpdater.ps1') + '"';
end;

function PsExe: String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

{ ---- tab-separated line -> list ---- }
procedure SplitTab(const S: String; Parts: TStringList);
var
  i: Integer;
  Cur: String;
begin
  Parts.Clear;
  Cur := '';
  for i := 1 to Length(S) do
    if S[i] = #9 then begin Parts.Add(Cur); Cur := ''; end
    else Cur := Cur + S[i];
  Parts.Add(Cur);
end;

procedure SelectWhere(const What: String);
var
  i: Integer;
  Parts: TStringList;
begin
  Parts := TStringList.Create;
  try
    for i := 0 to ProdList.Items.Count - 1 do
    begin
      SplitTab(ProdText[i], Parts);
      if What = 'all' then ProdList.Checked[i] := True
      else if What = 'none' then ProdList.Checked[i] := False
      else ProdList.Checked[i] := (Parts[4] = 'update');
    end;
  finally
    Parts.Free;
  end;
end;

procedure BtnAllClick(Sender: TObject);  begin SelectWhere('all');  end;
procedure BtnNoneClick(Sender: TObject); begin SelectWhere('none'); end;
procedure BtnUpdClick(Sender: TObject);  begin SelectWhere('upd');  end;

procedure ProdListClick(Sender: TObject);
var
  Parts: TStringList;
begin
  if (ProdList.ItemIndex < 0) or (ProdList.ItemIndex >= ProdText.Count) then Exit;
  Parts := TStringList.Create;
  try
    SplitTab(ProdText[ProdList.ItemIndex], Parts);
    ProdDesc.Caption := Parts[0] + ' ' + Parts[2] + ' - ' + Parts[5];
  finally
    Parts.Free;
  end;
end;

procedure LoadProducts;
var
  Lines: TArrayOfString;
  Parts: TStringList;
  i, rc: Integer;
  ListF, Sub: String;
begin
  ProdsLoaded := True;
  ExtractTemporaryFile('StorytoldUpdater.ps1');
  ListF := ExpandConstant('{tmp}\products.tsv');
  DeleteFile(ListF);
  ProdBusy.Caption := 'Contacting GitHub for the latest approved releases...';
  ProdBusy.Visible := True;
  ProdPage.Surface.Update;
  Exec(PsExe, '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\StorytoldUpdater.ps1') +
       '" -ListFile "' + ListF + '"', '', SW_HIDE, ewWaitUntilTerminated, rc);
  ProdList.Items.Clear;
  ProdNames.Clear;
  ProdText.Clear;
  if LoadStringsFromFile(ListF, Lines) then
  begin
    Parts := TStringList.Create;
    try
      for i := 0 to GetArrayLength(Lines) - 1 do
      begin
        if Trim(Lines[i]) = '' then Continue;
        SplitTab(Lines[i], Parts);
        if Parts.Count < 6 then Continue;
        { 0 name, 1 installed, 2 latest, 3 status, 4 action, 5 description }
        if Parts[1] = '' then Sub := 'new - ' + Parts[2]
        else if Parts[4] = 'update' then Sub := Parts[1] + '  ->  ' + Parts[2]
        else Sub := Parts[1] + ' (' + Parts[3] + ')';
        ProdList.AddCheckBox(Parts[0], Sub, 0, Parts[4] = 'update', True, False, False, nil);
        ProdNames.Add(Parts[0]);
        ProdText.Add(Lines[i]);
      end;
    finally
      Parts.Free;
    end;
    ProdBusy.Visible := False;
    ProdDesc.Caption := 'Click a product to see its description. Products already installed and out of date are pre-selected.';
  end else
  begin
    ProdBusy.Caption := 'Could not reach GitHub. You can still install the updater and pick products from it later.';
    ProdBusy.Visible := True;
  end;
end;

procedure InitializeWizard;
begin
  ProdNames := TStringList.Create;
  ProdText := TStringList.Create;

  { --- page: products --- }
  ProdPage := CreateCustomPage(wpSelectTasks, 'Products',
    'Choose which Storytold apps to install or update.');
  ProdList := TNewCheckListBox.Create(ProdPage);
  ProdList.Parent := ProdPage.Surface;
  ProdList.Left := 0; ProdList.Top := 0;
  ProdList.Width := ProdPage.SurfaceWidth;
  ProdList.Height := ProdPage.SurfaceHeight - 92;
  ProdList.OnClick := @ProdListClick;
  ProdList.OnClickCheck := @ProdListClick;

  ProdBusy := TNewStaticText.Create(ProdPage);
  ProdBusy.Parent := ProdPage.Surface;
  ProdBusy.Left := 0; ProdBusy.Top := ProdList.Height div 2;
  ProdBusy.Width := ProdPage.SurfaceWidth; ProdBusy.AutoSize := False;
  ProdBusy.Alignment := taCenter; ProdBusy.Visible := False;

  ProdDesc := TNewStaticText.Create(ProdPage);
  ProdDesc.Parent := ProdPage.Surface;
  ProdDesc.Left := 0; ProdDesc.Top := ProdList.Height + 6;
  ProdDesc.Width := ProdPage.SurfaceWidth; ProdDesc.Height := 36;
  ProdDesc.AutoSize := False; ProdDesc.WordWrap := True;

  BtnUpd := TNewButton.Create(ProdPage);
  BtnUpd.Parent := ProdPage.Surface; BtnUpd.Caption := 'Out-of-date only';
  BtnUpd.Left := 0; BtnUpd.Top := ProdList.Height + 48; BtnUpd.Width := 110; BtnUpd.Height := 24;
  BtnUpd.OnClick := @BtnUpdClick;
  BtnAll := TNewButton.Create(ProdPage);
  BtnAll.Parent := ProdPage.Surface; BtnAll.Caption := 'Select all';
  BtnAll.Left := 118; BtnAll.Top := BtnUpd.Top; BtnAll.Width := 90; BtnAll.Height := 24;
  BtnAll.OnClick := @BtnAllClick;
  BtnNone := TNewButton.Create(ProdPage);
  BtnNone.Parent := ProdPage.Surface; BtnNone.Caption := 'Select none';
  BtnNone.Left := 216; BtnNone.Top := BtnUpd.Top; BtnNone.Width := 90; BtnNone.Height := 24;
  BtnNone.OnClick := @BtnNoneClick;

  { --- page: product options --- }
  OptPage := CreateInputDirPage(ProdPage.ID, 'Product options',
    'Where should the apps go, and what should happen to old copies?',
    'Each app gets its own folder inside this one. Existing unzipped copies are moved here.',
    False, '');
  OptPage.Add('Apps folder:');
  OptPage.Values[0] := ExpandConstant('{localappdata}\Programs\Storytold');

  ChkKeep := TNewCheckBox.Create(OptPage);
  ChkKeep.Parent := OptPage.Surface;
  ChkKeep.Left := 0; ChkKeep.Top := 80; ChkKeep.Width := OptPage.SurfaceWidth;
  ChkKeep.Caption := 'Keep the old unzipped folders and zip files (default: delete them after a successful update)';
  ChkStart := TNewCheckBox.Create(OptPage);
  ChkStart.Parent := OptPage.Surface;
  ChkStart.Left := 0; ChkStart.Top := 108; ChkStart.Width := OptPage.SurfaceWidth;
  ChkStart.Caption := 'Create a Start Menu shortcut for newly installed apps'; ChkStart.Checked := True;
  ChkExplorer := TNewCheckBox.Create(OptPage);
  ChkExplorer.Parent := OptPage.Surface;
  ChkExplorer.Left := 0; ChkExplorer.Top := 136; ChkExplorer.Width := OptPage.SurfaceWidth;
  ChkExplorer.Caption := 'Restart Explorer when done so updated taskbar pins refresh (briefly flashes the taskbar)';
end;

procedure DeinitializeSetup;
begin
  ProdNames.Free;
  ProdText.Free;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = ProdPage.ID) and (not ProdsLoaded) then
    LoadProducts;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
var
  i: Integer;
  Any: Boolean;
begin
  Result := False;
  { no point asking about folders/old copies if no product was ticked }
  if (OptPage <> nil) and (PageID = OptPage.ID) then
  begin
    Any := False;
    for i := 0 to ProdList.Items.Count - 1 do
      if ProdList.Checked[i] then Any := True;
    Result := not Any;
  end;
end;

{ ---- writing config + running the product install ---- }
function JsonPath(const P: String): String;
begin
  Result := P;
  StringChangeEx(Result, '\', '\\', True);
end;

function B(V: Boolean): String;
begin
  if V then Result := 'true' else Result := 'false';
end;

procedure WriteConfig;
var
  Dir: String;
begin
  Dir := ExpandConstant(CONFIG_DIR);
  ForceDirectories(Dir);
  SaveStringToFile(Dir + '\config.json',
    '{"installRoot":"' + JsonPath(OptPage.Values[0]) + '","keepOld":' + B(ChkKeep.Checked) +
    ',"restartExplorer":' + B(ChkExplorer.Checked) + ',"startShortcut":' + B(ChkStart.Checked) + '}', False);
end;

procedure InstallProducts;
var
  i, rc, Tries: Integer;
  Names, LogF, Args, Failures: String;
  Lines: TArrayOfString;
  Finished: Boolean;
begin
  Names := '';
  for i := 0 to ProdList.Items.Count - 1 do
    if ProdList.Checked[i] then
    begin
      if Names <> '' then Names := Names + ',';
      Names := Names + ProdNames[i];
    end;
  if Names = '' then Exit;

  WriteConfig;
  LogF := ExpandConstant(CONFIG_DIR) + '\install.log';
  DeleteFile(LogF);
  Args := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\StorytoldUpdater.ps1') +
          '" -Install ' + Names + ' -LogFile "' + LogF + '"';

  WizardForm.StatusLabel.Caption := 'Installing products (downloads are large - this can take several minutes)...';
  WizardForm.ProgressGauge.Style := npbstMarquee;
  Exec(PsExe, Args, '', SW_HIDE, ewNoWait, rc);

  Finished := False;
  Tries := 0;
  while (not Finished) and (Tries < 6000) do   { ~30 minutes max }
  begin
    Sleep(300);
    Tries := Tries + 1;
    PumpMessages;
    if LoadStringsFromFile(LogF, Lines) and (GetArrayLength(Lines) > 0) then
    begin
      WizardForm.FilenameLabel.Caption := Trim(Lines[GetArrayLength(Lines) - 1]);
      Finished := Lines[GetArrayLength(Lines) - 1] = 'DONE';
    end;
  end;
  WizardForm.ProgressGauge.Style := npbstNormal;

  Failures := '';
  if LoadStringsFromFile(LogF, Lines) then
    for i := 0 to GetArrayLength(Lines) - 1 do
      if (Pos('FAILED', Lines[i]) > 0) or (Pos('ERROR', Lines[i]) = 1) then
        Failures := Failures + #13#10 + Trim(Lines[i]);
  if not Finished then
    Failures := Failures + #13#10 + 'Timed out waiting for the product install; see ' + LogF;
  if Failures <> '' then
    MsgBox('The updater is installed, but some products did not install:' + #13#10 + Failures + #13#10#13#10 +
           'Full log: ' + LogF, mbError, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    InstallProducts;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  i: Integer;
  S: String;
begin
  S := '';
  for i := 0 to ProdList.Items.Count - 1 do
    if ProdList.Checked[i] then S := S + NewLine + Space + ProdNames[i];
  Result := MemoDirInfo + NewLine + NewLine + MemoTasksInfo + NewLine + NewLine + 'Products to install or update:';
  if S = '' then Result := Result + NewLine + Space + '(none)'
  else Result := Result + S + NewLine + NewLine + 'Apps folder:' + NewLine + Space + OptPage.Values[0];
end;
