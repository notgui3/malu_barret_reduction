import matplotlib.pyplot as plt
import statistics as stats
from collections import Counter

nums = {}
nums_2 = {}

iter = "1000"

with open("RSA_9800x3d.txt", "r", encoding="utf-8") as file:
    for line in file:
        iters = line.strip().split(",")[0]
        speedup = int(float(line.strip().split(",")[1]))
        speedup_2 = float(line.strip().split(",")[1])


        # Integer
        if(nums.get(iters, 0) == 0):
            nums[iters] = {}
    
        if(nums.get(iters, {}).get(speedup, 0) == 0):
            nums[iters][speedup] = 1
        else:
            nums[iters][speedup] += 1


        # Floating point
        if(nums_2.get(iters, 0) == 0):
            nums_2[iters] = {}
    
        if(nums_2.get(iters, {}).get(speedup_2, 0) == 0):
            nums_2[iters][speedup_2] = 1
        else:
            nums_2[iters][speedup_2] += 1

graphing = nums[iter]
graphing_2 = nums_2[iter]

categories = list(graphing.keys())
frequencies = list(graphing.values())

stdev = stats.stdev(Counter(graphing_2).elements())
median_value = stats.median(Counter(graphing_2).elements())
mean = stats.mean(Counter(graphing_2).elements())

plt.bar(categories, frequencies, color='skyblue', edgecolor='black')

plt.xlabel('Speedups')
plt.ylabel('Frequency')
plt.title(f'Intel I7 1355u, {iter}, (Median: {median_value:.2f}, Mean: {mean:.2f}, StDev: {stdev:.2f})')

plt.show()


print(median_value, stdev, mean)

