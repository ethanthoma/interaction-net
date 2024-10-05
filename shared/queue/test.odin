package queue

import "base:intrinsics"
import "core:fmt"
import "core:testing"
import "core:thread"
import "core:time"

@(test)
test :: proc(t: ^testing.T) {
	CAPACITY :: 1 << 15
	NUM_THREADS :: 32
	NUM_ITEMS_PER_THREAD :: CAPACITY / NUM_THREADS

	q: Queue(int) = ---
	init(&q, CAPACITY)

	worker :: proc(q: ^Queue(int), id: int) {
		for i in 0 ..< NUM_ITEMS_PER_THREAD {
			elem := id * NUM_ITEMS_PER_THREAD + i
			for {
				ok := push(q, elem)

				if !ok {
					fmt.println("Failed to push, queue must be full, retrying...")
					thread.yield()
				} else {
					break
				}
			}
		}

		for i in 0 ..< NUM_ITEMS_PER_THREAD {
			for {
				elem, ok := pop(q)

				if !ok {
					fmt.println("Failed to pop, retrying...")
					thread.yield()
				} else {
					break
				}
			}
		}
	}

	stopwatch: time.Stopwatch
	time.stopwatch_start(&stopwatch)

	threads: [NUM_THREADS]^thread.Thread
	for &t, id in threads {
		t = thread.create_and_start_with_poly_data2(&q, id, worker)
	}

	for t in threads {
		thread.join(t)
	}

	time.stopwatch_stop(&stopwatch)

	duration := time.stopwatch_duration(stopwatch)
	seconds := time.duration_seconds(duration)

	fmt.printfln("Time:\t%v", duration)
	fmt.printfln(
		"Million Nums pushed and popped per second:\t%f",
		(2 * f64(CAPACITY) / 1_000_000) / seconds,
	)
}
