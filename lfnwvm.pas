unit lfnwVM;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  PByteArray = ^ByteArray;
  ByteArray = Array of Byte;

  EVMType = (EVMInt, EVMSingle, EVMDouble, EVMBool, EVMByte, EVMWord, EVMString);

  PVMState = ^VMState;

  VMOpFunc = procedure(state : PVMState); (* Procedures might be a little faster *)

  VMState = record
    SM : ByteArray; (* Stack Memory *)
    PM : ByteArray; (* Program Memory *)
    HM : ByteArray; (* Heap Memory *)
    RM : Array[0..255] of Byte; (* Register Memory *)

    SP : Cardinal; (* Stack Pointer *)
    PC : Cardinal; (* Program Counter *)

    (* Handlers for all OpCodes in our VM *)
    OpCodeHandlers : Array[0..255] of VMOpFunc;
  end;



function VM_NewState(StackSize : Cardinal; HeapSize : Cardinal; CodeFile : AnsiString) : PVMState;
procedure VM_FreeState(state : PVMState);

procedure VM_Run(state : PVMState);


procedure VM_RegisterOpHandler(state : PVMState; code : Byte; func : VMOpFunc);

implementation

(* Private Op Handlers *)
(*
  Naming convention for handlers
    I - LongInteger (Little Endian)
    B - Byte
    C - Char* (C String)
    R - Register
    H - Heap Address (Little Endian)
    S - Stack Operation
    O - Output

    Modifiers
    i - indirection
    l - literal
    x - array, multiple of type

*)

(* HALT *)
procedure VM_OpHALT(state : PVMState);
begin
  state^.PC := Length(state^.PM);
end;

(* Move a constant integer into a Register *)
(* MOV   R1  xFEED0101 *)
procedure VM_OpMOV_RIl(state : PVMState);
var reg : Byte;

begin

end;

(* Move a value in a Register into another Register *)
(* MOV   R1  R2 *)
procedure VM_OpMOV_RR(state : PVMState);
begin

end;

(* Move a constant integer into a Heap Memory Address *)
(* MOV   @x00010000  x00000001 *)
procedure VM_OpMOV_HIl(state : PVMState);
var addr : LongInt;
    tmp : LongInt;
begin
  Move(state^.PM[state^.PC + 1], addr, 4);
  Move(state^.PM[state^.PC + 5], state^.HM[addr], 4);
  Move(state^.PM[state^.PC + 5], tmp, 4);
  WriteLn(addr, ' = ', tmp);
  state^.PC := state^.PC + 9;
end;

(* Copy from Heap Memory into Heap Memory for x num bytes *)
(* MOV   @x00010000  @x04010000  x04000000 *)
procedure VM_OpMOV_HHBx(state : PVMState);
var addrDest : LongInt;
    addrSrc : LongInt;
    count : LongInt;
begin
  Move(state^.PM[state^.PC + 1], addrDest, 4);
  Move(state^.PM[state^.PC + 5], addrSrc, 4);
  Move(state^.PM[state^.PC + 9], count, 4);

  Move(state^.HM[addrSrc], state^.HM[addrDest], count);

  state^.PC := state^.PC + 13;
end;

(* Output from Heap Memory to Console Integer *)
(* PRINTI @x00010000 *)
procedure VM_OpPRINT_HOI(state : PVMState);
var addr : LongInt;
    val : LongInt;
begin
  Move(state^.PM[state^.PC + 1], addr, 4);
  Move(state^.HM[addr], val, 4);

  WriteLn(val);

  state^.PC := state^.PC + 5;
end;

(* Output from Heap Memory to Console Char *)
(* PRINTC @x00010000  *)
procedure VM_OpPRINT_HOC(state : PVMState);
var addr : LongInt;
    val : Char;
begin
  Move(state^.PM[state^.PC + 1], addr, 4);
  Move(state^.HM[addr], val, 1);

  Write(val);

  state^.PC := state^.PC + 5;

end;

function VM_NewState(StackSize : Cardinal; HeapSize : Cardinal; CodeFile : AnsiString) : PVMState;
var state : PVMState;
    f : file;
    buf : Byte = 0;
    i : Integer;
    codeLength : Int64;
begin
  Result := nil;
  New(state);

  if FileExists(CodeFile) then
  begin
    (* Open and read all file bytes into ProgramMemory *)
    AssignFile(f, CodeFile);
    Reset(f, 1);
    codeLength := FileSize(f);
    SetLength(state^.PM, codeLength);
    i := 0;
    while not EOF(f) do
    begin
      BlockRead(f, buf, 1);
      state^.PM[i] := buf;
      Inc(i);
    end;

    CloseFile(f);
  end
  else
  begin
    (* Unable to open binary file *)
    WriteLn('Unable to locate file: ', CodeFile);
    Dispose(state);
    Exit();
  end;

  SetLength(state^.HM, HeapSize);
  SetLength(state^.SM, StackSize);

  (* Initialize Registers *)
  state^.PC := 0;
  state^.SP := 0;

  (* Register our handlers *)
  VM_RegisterOpHandler(state, 0, @VM_OpHALT);
  VM_RegisterOpHandler(state, 1, @VM_OpMOV_HIl);
  VM_RegisterOpHandler(state, 2, @VM_OpMOV_HHBx);
  VM_RegisterOpHandler(state, 3, @VM_OpPRINT_HOI);
  VM_RegisterOpHandler(state, 4, @VM_OpPRINT_HOC); // Special functionality, stops at first NULL (0) Byte


  Result := state;
end;

procedure VM_FreeState(state : PVMState);
begin
  if not Assigned(state) then
     Exit();

  SetLength(state^.SM, 0);
  SetLength(state^.HM, 0);
  SetLength(state^.PM, 0);

  Dispose(state);
end;

procedure VM_Run(state : PVMState);
var IsEnd : Boolean = False;
    CurOpCode : Byte;
    i, j : Integer;
begin

  (* Check that the state is ready *)

  (* Start looping over bytes calling OpCode handlers *)
  while not IsEnd do
  begin
    CurOpCode := state^.PM[state^.PC];
    state^.OpCodeHandlers[CurOpCode](state);

    if state^.PC = Length(state^.PM) then
       IsEnd := True;
  end;

  (* Dump Heap memory to console *)
  WriteLn('');
  for i := 0 to Length(state^.HM) - 1 do
  begin
    Write(HexStr(state^.HM[i], 2), ' ');

    if (i + 1) mod 8 = 0 then
    begin
      WriteLn();

      Inc(j);
      if j = 8 then
      begin
        WriteLn();
        WriteLn(i+1);
        j := 0;
      end;

    end;
  end;

end;


procedure VM_RegisterOpHandler(state : PVMState; code : Byte; func : VMOpFunc);
begin
  state^.OpCodeHandlers[code] := func;
end;

end.

