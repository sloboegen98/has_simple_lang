#!/bin/bash

rm -f ans.txt

touch ans.txt

for t in $(ls in/in*); do
    echo ${t}
    echo ${t} >> ans.txt
    cat ${t} >> ans.txt
    echo >> ans.txt 
    ./../parsertestexe $t >> ans.txt
    echo "------------------------" >> ans.txt
    echo >> ans.txt
done
