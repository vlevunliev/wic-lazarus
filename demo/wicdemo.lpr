program wicdemo;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, WicDemoMain;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
