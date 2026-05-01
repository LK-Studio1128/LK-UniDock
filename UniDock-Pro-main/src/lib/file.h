#ifndef VINA_FILE_H
#define VINA_FILE_H

#include "common.h"

struct file_error {
    path name;
    bool in;
    file_error(const path& name_, bool in_) : name(name_), in(in_) {}
};

#ifndef __CUDACC__
#include <boost/filesystem/fstream.hpp>

struct ifile : public boost::filesystem::ifstream {  // never use ifstream pointer to destroy ifile
                                                     // - no virtual destructors, possibly
    ifile(const path& name) : boost::filesystem::ifstream(name) {
        if (!(*this)) throw file_error(name, true);
    }
    ifile(const path& name, std::ios_base::openmode mode)
        : boost::filesystem::ifstream(name, mode) {
        if (!(*this)) throw file_error(name, true);
    }
};

struct ofile : public boost::filesystem::ofstream {  // never use ofstream pointer to destroy ofile
                                                     // - no virtual destructors, possibly
    ofile(const path& name) : boost::filesystem::ofstream(name) {
        if (!(*this)) throw file_error(name, false);
    }
    ofile(const path& name, std::ios_base::openmode mode)
        : boost::filesystem::ofstream(name, mode) {
        if (!(*this)) throw file_error(name, false);
    }
};
#else
#include <fstream>

struct ifile : public std::ifstream {
    ifile(const path& name) : std::ifstream(name) {
        if (!(*this)) throw file_error(name, true);
    }
    ifile(const path& name, std::ios_base::openmode mode)
        : std::ifstream(name, mode) {
        if (!(*this)) throw file_error(name, true);
    }
};

struct ofile : public std::ofstream {
    ofile(const path& name) : std::ofstream(name) {
        if (!(*this)) throw file_error(name, false);
    }
    ofile(const path& name, std::ios_base::openmode mode)
        : std::ofstream(name, mode) {
        if (!(*this)) throw file_error(name, false);
    }
};
#endif

#endif
