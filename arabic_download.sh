#!/bin/bash -x

# this script downloads files from a list of files with a common URL prefix

# check if server is outputting the correct content length using curl -i

mirror="https://CHANGEME"
# url.lst is a list of file names without the mirror prefix

SIMULTANEOUSDOWNLOADS=5 # the script will START this number of downloads in background and will wait for ALL of them to finish before starting next batch

PARTSIZE=10485760
while true; do

    for file in $(tr -d '\r' <url.lst); do
        if [ -f "${file}" ]; then
            echo "File ${file} already exists, skipping download."
            continue
        fi
        size=$(curl -s -D - -o /dev/null --range 0-8 -m 10 "${mirror}/${file}" | awk '/Content-Length/ {print $2}' | tr -d '\r')
        if [ $size -lt $PARTSIZE ]; then
            curl -o "${file}" "${mirror}/${file}"
        else

            chunks=$(($size / $PARTSIZE))
            for ((i = 0; i <= chunks; i++)); do
                start=$((i * $PARTSIZE))
                end=$(((i + 1) * $PARTSIZE - 1))
                if [[ $i -eq $chunks ]]; then
                    end=$(($size - 1)) # end of the last chunk is size - 1
                fi
                expected_chunk_size=$((end - start + 1))
                part_number=$(printf "%010d" $i)
                (
                    while true; do
                        if [ -f "${file}".part"${part_number}" ] && [ $(stat -c%s "${file}.part${part_number}") -eq $expected_chunk_size ]; then
                            echo "Chunk ${file}.part${part_number} already exists and its size is correct, skipping download."
                            break
                        fi
                        curl -o "${file}".part"${part_number}" --range $start-$end "${mirror}/${file}" && break
                        echo "Download failed, retrying..."
                        sleep 100
                    done
                ) &
                if [[ $(((i + 1) % $SIMULTANEOUSDOWNLOADS)) == 0 ]]; then
                    wait # Wait for all background jobs to finish
                fi
            done
            wait # Wait for any remaining background jobs to finish

            ls "${file}".part* | sort -n | xargs cat >"${file}"
            rm "${file}".part*
        fi
    done

done
