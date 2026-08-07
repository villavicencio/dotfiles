import subprocess, time, os
budget = 300
env = dict(os.environ); env["TERM_PROGRAM"]="x"; env["TMUX"]=""
ts=[]
for _ in range(10):
    t=time.perf_counter()
    subprocess.run(["zsh","-i","-c","true"], env=env, capture_output=True)
    ts.append((time.perf_counter()-t)*1000)
ts.sort()
med=(ts[4]+ts[5])/2; mx=ts[-1]
print("startup (ms):", [round(x) for x in ts])
print(f"median {med:.0f} ms  max {mx:.0f} ms  budget {budget} ms")
raise SystemExit(0 if med <= budget else 1)
