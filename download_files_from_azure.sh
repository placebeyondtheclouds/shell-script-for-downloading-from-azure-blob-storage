#!/bin/bash -x

mirror="https://azureopendatastorage.blob.core.windows.net/openstt/ru_open_stt_opus"
SIMULTANEOUSDOWNLOADS=10 # the script will START this number of downloads in background and will wait for ALL of them to finish before starting next batch

while true; do

        for file in $(cut -f2 -d' ' md5sum.lst); do
                mkdir -p $(dirname ${file})
                if [ -f ${file} ]; then
                        echo "File ${file} already exists, skipping download."
                        continue
                fi
                size=$(curl -sI "${mirror}/${file}" | awk '/Content-Length/ {print $2}' | tr -d '\r')
                if [ $size -lt 104857600 ]; then
                        curl -o ${file} "${mirror}/${file}" # for small files, download the whole file at once
                else
                        chunks=$((size / 104857600)) # 100MB in bytes
                        for ((i = 0; i <= chunks; i++)); do
                                start=$((i * 104857600))         # 100MB in bytes
                                end=$(((i + 1) * 104857600 - 1)) # 100MB in bytes
                                if [[ $i -eq $chunks ]]; then
                                        end=$((size - 1)) # end of the last chunk is size - 1
                                fi
                                expected_chunk_size=$((end - start + 1))
                                part_number=$(printf "%010d" $i) # enough zeros hahahaha
                                (
                                        while true; do
                                                if [ -f ${file}.part${part_number} ] && [ $(stat -c%s "${file}.part${part_number}") -eq $expected_chunk_size ]; then
                                                        echo "Chunk ${file}.part${part_number} already exists and its size is correct, skipping download."
                                                        break
                                                fi
                                                curl -o ${file}.part${part_number} "${mirror}/${file}" --range $start-$end && break
                                                echo "Download failed, retrying..."
                                                sleep 1
                                        done
                                ) &
                                if [[ $(((i + 1) % $SIMULTANEOUSDOWNLOADS)) == 0 ]]; then
                                        wait # Wait for all background jobs to finish
                                fi
                        done
                        wait                                            # Wait for any remaining background jobs to finish
                        ls ${file}.part* | sort -n | xargs cat >${file} # this sorting part is not important if the part's numbers are padded with enough zeros
                        rm ${file}.part*
                fi
        done

        echo ''
        echo '>>> Checking MD5 digests...'

        md5sum -c md5sum.lst 1>md5sum.log 2>/dev/null
        status=$?

        if test $status -eq 0; then
                rm md5sum.log
                echo '>>> Data is downloaded and checked.'
                break
        fi

        for failed in $(grep 'FAILED$' md5sum.log | grep -Po '^[^:]+'); do
                echo ">>> MD5 digest for ${failed} is incorrect, the file will be downloaded again."
                rm -f ${failed}
        done

        echo ''
done
