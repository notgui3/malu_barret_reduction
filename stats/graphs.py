import matplotlib.pyplot as plt
import statistics as stats
from collections import Counter

nums = {}

with open("speedup_1355u.txt", "r", encoding="utf-8") as file:
    for line in file:
        iters = line.strip().split(",")[0]
        speedup = int(float(line.strip().split(",")[1]))

        if(nums.get(iters, 0) == 0):
            nums[iters] = {}
    
        if(nums.get(iters, {}).get(speedup, 0) == 0):
            nums[iters][speedup] = 1
        else:
            nums[iters][speedup] += 1

graphing = nums["10"]
categories = list(graphing.keys())
frequencies = list(graphing.values())

plt.bar(categories, frequencies, color='skyblue', edgecolor='black')

plt.xlabel('Speedups')
plt.ylabel('Frequency')
plt.title('Histogram of Dictionary Frequencies')

plt.show()

median_value = stats.median(Counter(graphing).elements())

print(median_value)
