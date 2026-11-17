import sys,re,glob,os
checks={
 'review-reduction-kernels-for-mi300x':{'E1 fence':r'threadfence|memory fence|__atomic.*release|fence','E1b XCD/L2':r'XCD|L2','E2 CU 304/1216':r'1216|304','E3 64 KiB':r'64 ?KiB|65536|64 ?KB','E4 last error':r'last error|sticky|cudaGetLastError\(\).*(abort|before)|clear'},
 'compat-shim-stand-in-across-rocm-releases':{'E1 newer ROCm provides':r'10\.1|7\.16|newer ROCm|later ROCm|redefinition','E2 gate HIP_VERSION':r'HIP_VERSION|__has_include|feature (test|check|probe)','E3 test current release':r'current (ROCm )?release|latest ROCm|newer release|10\.1'},
 'existing-amd-fork-linked-in-readme':{'E1 URL':r'github\.com/anthonix','E2 authoritative':r'authoritative|community','E3 links-not-merges':r'link(s|ing)? .*fork|does not want|may not (accept|want)|contribut(e|ing) to the fork','E4 PR/web search':r'gh pr|pull request|PR search|web search|search'},
}
for d in sorted(glob.glob(sys.argv[1])):
    eid=os.path.basename(d.rstrip('/'))
    if eid not in checks: continue
    f=[x for x in glob.glob(d+'/work/*.md')+glob.glob(d+'*-work/work/*.md')]
    t=open(f[0]).read() if f else ''
    print(d.split('/')[-2][:22],eid[:28],'file' if f else 'NOFILE',' '.join(f"{k}:{'Y' if re.search(v,t,re.I) else '-'}" for k,v in checks[eid].items()))
