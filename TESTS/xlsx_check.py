# Run after `npm test` (it writes /tmp/out.xlsx): opens the generated file with openpyxl, an independent xlsx reader.
import openpyxl
ws=openpyxl.load_workbook('/tmp/out.xlsx').active
assert ws.title=='by_exam' and [c.value for c in ws[1]]==['label','avg','n'] and [c.value for c in ws[2]]==['A & <B>',75.5,3],[[c.value for c in r] for r in ws.iter_rows()]
print('xlsx opens in openpyxl: OK')
