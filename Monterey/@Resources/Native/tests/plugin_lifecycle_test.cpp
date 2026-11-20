#define NOMINMAX
#include <windows.h>
#include <dbghelp.h>
#include <iostream>
#include <thread>
#include <chrono>
#include <vector>
#include <cassert>

LONG WINAPI dumpException(EXCEPTION_POINTERS* info) {
    if(info->ExceptionRecord->ExceptionCode!=EXCEPTION_ACCESS_VIOLATION) return EXCEPTION_CONTINUE_SEARCH;
    auto process=GetCurrentProcess(); SymInitialize(process,nullptr,TRUE);
    auto context=*info->ContextRecord;
    STACKFRAME64 frame{};
    frame.AddrPC.Offset=context.Rip; frame.AddrPC.Mode=AddrModeFlat;
    frame.AddrStack.Offset=context.Rsp; frame.AddrStack.Mode=AddrModeFlat;
    frame.AddrFrame.Offset=context.Rbp; frame.AddrFrame.Mode=AddrModeFlat;
    std::cerr<<"Access violation at "<<std::hex<<context.Rip<<" stack:\n";
    for(int i=0;i<30 && StackWalk64(IMAGE_FILE_MACHINE_AMD64,process,GetCurrentThread(),&frame,&context,nullptr,SymFunctionTableAccess64,SymGetModuleBase64,nullptr);++i) {
        char storage[sizeof(SYMBOL_INFO)+MAX_SYM_NAME]{}; auto* symbol=reinterpret_cast<SYMBOL_INFO*>(storage); symbol->SizeOfStruct=sizeof(SYMBOL_INFO);symbol->MaxNameLen=MAX_SYM_NAME;
        DWORD64 offset=0; IMAGEHLP_LINE64 line{};line.SizeOfStruct=sizeof(line);DWORD displacement=0;
        if(SymFromAddr(process,frame.AddrPC.Offset,&offset,symbol)) std::cerr<<symbol->Name<<"+"<<offset;
        else std::cerr<<std::hex<<frame.AddrPC.Offset;
        if(SymGetLineFromAddr64(process,frame.AddrPC.Offset,&displacement,&line))std::cerr<<" "<<line.FileName<<":"<<line.LineNumber;
        std::cerr<<"\n";
    }
    std::cerr.flush();
    return EXCEPTION_CONTINUE_SEARCH;
}
int wmain(int argc,wchar_t** argv) {
    if(argc!=2)return 2;
    AddVectoredExceptionHandler(1,dumpException);
    auto dll=LoadLibraryW(argv[1]);if(!dll)return 3;
    auto init=reinterpret_cast<void(*)(void**,void*)>(GetProcAddress(dll,"Initialize"));
    auto update=reinterpret_cast<double(*)(void*)>(GetProcAddress(dll,"Update"));
    auto get=reinterpret_cast<wchar_t const*(*)(void*)>(GetProcAddress(dll,"GetString"));
    auto finalize=reinterpret_cast<void(*)(void*)>(GetProcAddress(dll,"Finalize"));
    for(int cycle=0;cycle<50;++cycle) {
        std::vector<void*> measures(6);
        for(auto& data:measures) {init(&data,nullptr);if(!data)return 4;}
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        for(auto data:measures){update(data);if(!get(data))return 5;}
        for(auto data:measures)finalize(data);
    }
    FreeLibrary(dll);
    std::cout<<"PASS: 50 lifecycle cycles, 300 measures\n";
}
