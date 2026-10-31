## Step 10. How close is a rerun to the first analysis?

The results of a rerun of the workflow are compared with the first analysis, the one reported here. `validation/expected.tsv` lists the measures of that analysis (written by `scripts/10_validate.py make-expected`) with the variation that is usual for each. Nothing is judged as pass or fail and the comparison never makes the run FAILED: for every value the report gives the value of the rerun, the value of the first analysis, the difference in percent and a note, "within the usual variation" or "larger than usual". A value that is larger than usual usually means that the data or the programs differ from the first analysis (for example a newer release of the Swiss-Prot proteins, or other versions of the programs), and it is a reason to look at the data used, not a failure.

The usual variation of each kind of value is:

* the measures of Hw 2.1 (mean of the three polished runs): the range seen over the runs, widened on both sides by that range or by 0.5 percent of the mean, whichever is larger; 1 percent for the measures that use the Swiss-Prot proteins, and 1.5 percent for the transcript measures (Trinity gives a slightly different assembly at every run);
* the measures of Hw 2.0, which does not depend on any assembler: 0.2 percent, and 1 percent or 1.5 percent for the Swiss-Prot and transcript measures;
* the measures of the control assemblies (a single run each of programs whose results vary between computers): 25 percent;
* the numbers of reads of the two PacBio sets and the checksum of the sequences of the assembly are compared exactly and reported as "same" or "differs". The checksum is the md5 of the contig sequences with names and orientation ignored: the sequences of the assembly are identical to those of the first analysis when it is the same.

```bash
cd $HW
python3 scripts/10_validate.py check results     # after steps 04 to 09 have been rerun; give the results folder of the rerun
```

The report `results/10_validation/validation_report.txt` starts with a summary (how many values are within the usual variation, and whether the sequences of the assembly and the numbers of reads are the same), followed by one line per value; `results/10_validation/closeness.tsv` holds the same values as a table. When only some steps have been rerun, the values of the others are "not available".
