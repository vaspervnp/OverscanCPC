10 REM ---------------------------------------------------------------
20 REM LOUKOUMAS - loader. Puts the REVIVE8BIT screen up, then starts
30 REM the game on space or after ten seconds, whichever comes first.
40 REM Saved on the disc as ASCII, so this file is also its own listing.
50 REM ---------------------------------------------------------------
60 MODE 0:BORDER 0
70 REM The sixteen inks the picture was drawn in - assets/revive8b.txt.
80 INK 0,0:INK 1,13:INK 2,26:INK 3,15
90 INK 4,25:INK 5,10:INK 6,3:INK 7,1
100 INK 8,11:INK 9,23:INK 10,6:INK 11,24
110 INK 12,20:INK 13,16:INK 14,12:INK 15,4
120 LOAD"REVIVE8B.SCR",&C000
130 REM TIME counts three hundred to the second.
140 t=TIME+3000
150 IF INKEY(47)<>-1 THEN 180
160 IF TIME<t THEN 150
170 REM Out of time, or space went down.
180 RUN"LOUK.BIN"
