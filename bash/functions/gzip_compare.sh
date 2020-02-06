#!/usr/bin/env bash

# Compare original and gzipped file size
function gzip_compare() {
	origsize=$(wc -c < "$1");
	gzipsize=$(gzip -c "$1" | wc -c);
	ratio=$(echo "$gzipsize * 100 / $origsize" | bc -l);

	local origsize, gzipsize, ratio

	printf "orig: %d bytes\n" "$origsize";
	printf "gzip: %d bytes (%2.2f%%)\n" "$gzipsize" "$ratio";
}
