import json
import sys

skipped = 0
total_skipped = 0

def print_skipped():
	global skipped
	global total_skipped
	
	if skipped > 0:
		print 'JSON PRETTYFIER: {0} line(s) skipped'.format(skipped)
		total_skipped += skipped
		skipped = 0

try:
	while True:
		line = sys.stdin.readline()
		if not line:
			break

		try:
			json_data = json.loads(line)
		except ValueError:
			skipped += 1
			print line,
			continue

		output = json.dumps(json_data, sort_keys=False, indent=4)
		print_skipped()
		print output
except:
	print "Unexpected error:", sys.exc_info()[0]
	sys.exit(255)

print_skipped()
print "JSON PRETTYFIER: {0} total lines(s) skipped.".format(total_skipped)

